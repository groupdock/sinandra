require 'rubygems'

class String
  def to_slug
    str = self.gsub('&', 'and').gsub(' ', '-')
    str = str.gsub(/\W+/, '-').gsub(/^-+/,'').gsub(/-+$/,'').downcase
  end
end
