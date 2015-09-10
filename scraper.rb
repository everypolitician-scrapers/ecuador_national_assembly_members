# #!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'nokogiri'
require 'net/http'
require 'open-uri/cached'
require 'json'

OpenURI::Cache.cache_path = '.cache'

class String
  def tidy
    self.gsub(/[[:space:]]+/, ' ').strip
  end
end

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

def get_contacts(cell)
    contacts = {}
    cell.css('p.left a').each do |contact|
        url = contact.css('@href').to_s
        type = contact.css('@alt').to_s
        contacts[:facebook] = url if type.index('Facebook')
        contacts[:twitter] = url if type.index('Twiter')
    end

    return contacts
end

# the lists of who is in which party are fetched by JS when you click
# an icon so get all this first and then turn it into a uid -> party
# lookup
def get_party_data(noko)
    members = {}
    noko.css('div.section-container section').each do |section|
        id = section.css('@id').first.to_s
        next if not id.index('lresult')
        id = id.gsub('lresult-', '')
        party = section.css('p.title a').first.text.to_s.tidy
        uri = URI('http://www.asambleanacional.gob.ec/es/pleno-asambleistas/getPartidos')
        data = Net::HTTP.post_form(uri, 'idPartido' => id)
        party_data = JSON.parse(data.body)
        party_data['data'].each do |member|
            members[member['uid']] = party
        end
    end

    return members
end

# they have gendered icons in the map of the chamber although the names
# are inconsistent
# this does not work for the president and vice presidents though
def get_gender(icon)
    return 'male' if icon.index('masculino')
    return 'male' if icon.index('hombre')
    return 'male' if icon.index('man')
    return 'female' if icon.index('femenino')
    return 'female' if icon.index('woman')
    return 'female' if icon.index('mujer')
end

def scrape_list(url)
    noko = noko_for(url)
    party_for_member = get_party_data(noko)
    wrapper = noko.css('div#wrapper')
    wrapper.css('div.pin').each do |person|
        trs = person.css('table tr')
        name = trs[0].css('td strong').inner_html.split('<br>').first.to_s.tidy
        area = trs[0].css('td em').text.split('por').last.to_s.tidy
        img = trs[1].css('td img/@src').first.to_s
        # unset placeholder image
        img = '' if img.index('mystery-man')

        # the id in the image matches the uid from the party lists
        # collected earlier so extract that
        id = img.gsub(/.*picture-/, '').gsub(/-.*$/, '')
        party = party_for_member[id]

        # there is the odd row with duplicated data but no id.
        next if not id

        contacts = get_contacts(trs[1])

        # the gendered icon is in a separate dive from the main details
        # and the easiest way to look it up is to use the positioning data
        xpos = person.css('@data-xpos').to_s
        ypos = person.css('@data-ypos').to_s
        style = 'left:' + xpos + 'px;top:' + ypos + 'px;'
        extra = wrapper.xpath('//div[@style="' + style + '"]')
        icon = extra.css('img/@src').to_s
        gender = get_gender(icon)

        data = {
            id: id,
            name: name,
            area: area,
            img: img,
            faction: party,
            gender: gender,
        }

        data = data.merge(contacts)

        ScraperWiki.save_sqlite([:id], data)
    end
end


scrape_list('http://www.asambleanacional.gob.ec/es/pleno-asambleistas')
