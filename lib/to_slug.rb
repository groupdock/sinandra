require 'rubygems'
require 'unicode'

class String
  def to_slug
    str = self.gsub('&', 'and')
    str = Unicode.normalize_KD(str).gsub(/[^\x00-\x7F]/n,'')
    str = str.gsub(/\W+/, '-').gsub(/^-+/,'').gsub(/-+$/,'').downcase
  end
end
