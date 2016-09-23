# NER annotation interface for Dalphi

This interface can be used to annotate annotation-documents for NER applications. Integrate it to your [DALPHI](https://github.com/Dalphi/dalphi) project by copy'n'pasteing the HTML / CoffeeScript / SCSS source codes.

![screen shot 16-09-23](ScreenShot16-09-23.png)

## Interactions / how to use

The *NER complete* interfaces recognises the following commands:

- **mouse actions**
	- click:
		- on an unannotated token: Start a new annotation with this token
		- on an annotated token: select this token (chunk of belonging tokens)

- **keyboard commands** work on currently selected tokens (chunk of tokens)
	- backspace: remove the annotation
	- 1: annotate as "PER"
	- 2: annotate as "COM"
	- tab: change the token selection to the right / to the bottom
	- tab + shift: change the token selection to the left / to the top
	- right arrow: extend the annotation with the next token to the right
	- right arrow + shift: shrink the annotation by removing the right most outer token
	- left arrow: extend the annotation with the next token to the left
	- left arrow + shift: shrink the annotation by removing the left most outer token

See the [issue list](https://github.com/Dalphi/interface-ner_complete/issues) for upcoming features or to create a new issue if a necessary interaction is missing.

## Expected payload

All Dalphi interfaces expects payload to render. Payload for this interface must have the following structure. A `content` objects is an array of paragraphs. Each paragraph is an array of sentences. Each sentence is an array of tokens, which are text elements like words or symbols.

```
{
  "content": [
    [
      [
        {"term": "One"},
        {"term": "sentence"},
        {"term": "."}
      ],
      [
        {"term": "Another"},
        {"term": "one"},
        {"term": ","},
        {"term": "same"},
        {"term": "paragraph"},
        {"term": "."}
      ]
    ],
    [
      [
        {"term": "Another"},
        {"term": "paragraph"},
        {"term": "."}
      ]
    ]
  ]
}
```
An annotated token will have an `annotation` object, additionally to it's `term` value. This `annotation` object contains a `label` value to save your annotation and a `length` value, specifying how many following tokens this annotation has. The following example is an annotation of the two words "Jane Doe" as "PER":

```
{
  "term": "Jane",
  "annotation": {
    "label": "PER",
    "length": 2
  }
},
{"term": "Doe"}
```
The file `test_payload.json` offers a short text written in german in this format containing three paragraphs, three person names ("PER") and one company name ("COM").

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added awesome feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## License

See [LICENSE](https://raw.githubusercontent.com/Dalphi/interface-ner_complete/master/LICENSE).

## About

This interface as well as DALPHI is maintained and funded by [Implisense](http://implisense.com/).

We love open source software and are [hiring](http://implisense.com/en/jobs/)!
