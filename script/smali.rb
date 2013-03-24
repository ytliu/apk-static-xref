class Smali_Function

  TYPE_STR = {
    'V'=>'void',
    'Z'=>'boolean',
    'B'=>'byte',
    'S'=>'short',
    'C'=>'char',
    'I'=>'int',
    'J'=>'long',
    'F'=>'float',
    'D'=>'double'
  }

  def initialize
    @cls = nil
    @mtd = nil
    @pty = nil
    @rettype = nil
    @para = []
  end

  # Method parameters types
  def extractCallParameters(line)
    useful_parts = line.split(' ')[-1][1..-1]
    para_str = useful_parts.split('(')[1].split(')')[0]
    temp_para = Array.new
    array = false
    while para_str.length > 0
      i = 0
      if i < para_str.length
        if para_str[i] == 'L'
          while (para_str[i] != ';') and (i < para_str.length)
            i += 1
          end
          if array
            temp_para << (para_str[1...i] + "[]")
            array = false
          else
            temp_para << para_str[1...i]
          end
          para_str = para_str[i+1..-1]
        elsif para_str[i] == '['
          array = true
          while para_str[i] == '['
            i += 1
          end
          para_str = para_str[i..-1]
        else
          value = TYPE_STR[para_str[i]]
          if array
            temp_para << (value + "[]")
            array = false
          else
            temp_para << value
          end
          para_str = para_str[i+1..-1]
        end
      end
    end
    @para = temp_para 
  end

  # Method return type
  def extractReturnType(line)
    useful_parts = line.split(' ')[-1][1..-1]
    retval = line.split(')')[1]
    ## TODO: and.. what about array on return types?
    value = (retval.length == 1) ? TYPE_STR[retval] : retval[1...-1]
    @rettype = value
  end

  # Method proto
  def extractProto(line)
    useful_parts = line.split(' ')[-1]
    @pty = "(" + useful_parts.split('(')[-1]
  end

  def str
    "#{@cls}->#{@mtd}#{@pty}"
  end
end

class Invoked < Smali_Function
  attr_reader :cls, :mtd, :pty
  def initialize(smali_invoke_line)
    super()
    extractOwnerClass(smali_invoke_line)
    extractMethodName(smali_invoke_line)
    extractProto(smali_invoke_line)
    extractCallParameters(smali_invoke_line)
    extractReturnType(smali_invoke_line)
  end

  # Method class owner extractor
  def extractOwnerClass(line)
    useful_parts = line.split(' ')[-1][1..-1]
    @cls = useful_parts.split('-')[0][0...-1]
  end

  #Method name extractor
  def extractMethodName(line)
    useful_parts = line.split(' ')[-1]
    useful_parts = useful_parts.split('->')[1]
    @mtd = useful_parts.split('(')[0]
  end
end

class Invoker < Smali_Function
  attr_reader :cls, :mtd, :pty
  def initialize(cls, smali_line)
    super()
    @cls = cls
    extractMethodName(smali_line)
    extractProto(smali_line)
    extractCallParameters(smali_line)
    extractReturnType(smali_line)
  end

  #Method name extractor
  def extractMethodName(line)
    useful_parts = line.split(' ')[-1]
    @mtd = useful_parts.split('(')[0]
  end
end