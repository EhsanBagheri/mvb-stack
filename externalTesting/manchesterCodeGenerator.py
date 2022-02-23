import os
import random
import sys
import csv

class manchesterCodeGenerator:
    def __init__(self, default_length):
        self.currentSequence = list()     # stores random 0-1 sequenece
        self.currentManchester = list()   # stores currentS in manchester coding

        self.currentSequence = self.generateRandomSequence(default_length)
        self.currentManchester = self.codeToManchester(self.currentSequence)

    @staticmethod
    def generateRandomSequence(length: int):
        sequence = list()
        for i in range(length):
            sequence.append(random.randint(0, 1))
        return sequence

    @staticmethod
    def codeToManchester(sequence: list):
        # encode squence to manchester, return None if input is faulty
        new_sequence = list()

        for i in sequence:
            if i == 0:
                new_sequence.append(0)
                new_sequence.append(1)
            elif i == 1:
                new_sequence.append(1)
                new_sequence.append(0)
            else:
                return None

        return new_sequence

    def dumpManchesterToFile(self):
        with open('generated_manchester.csv', 'w') as fp:
            write = csv.writer(fp)

            write.writerow(self.currentManchester)



def __main__(argv):
    code_generator = manchesterCodeGenerator(32)
    print(code_generator.currentSequence)
    print(code_generator.currentManchester)
    code_generator.dumpManchesterToFile()

if __name__ == '__main__':
    __main__(sys.argv)
    pass
