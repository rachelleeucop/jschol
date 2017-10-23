// ##### Recent Articles sidebar widget ##### //

import React from 'react'
import { Link } from 'react-router'
import ArbitraryHTMLComp from "../components/ArbitraryHTMLComp.jsx"
import TruncationObj from '../objects/TruncationObj.jsx'

class AuthorsComp extends React.Component {
  render() {
    let authorList = this.props.authors.map(function(author, i, a) {
        return (<li key={i}>{author.name}</li>)
      })
    return (
      <div className="c-authorlist">
        <TruncationObj element="ul" className="c-authorlist__list"
                    options={{watch:'window', after:'.c-authorlist__list-ellipsis', ellipsis:' ', wrap:'children'}}>
         {authorList}
         <li><span className="c-authorlist__list-ellipsis">&nbsp;...</span></li>
        </TruncationObj>
      </div>
    )
  }
}

export default class RecentArticlesComp extends React.Component
{
  render = () =>
    <ul className="c-relateditems">
  { this.props.data.items.map(item =>
      <li key={item.id}>
        <h3>
          {/* Workaround for conflict between React and jquery.dotdotdot: we can't use a
              <Link> within truncated content. So, fall back to a plain ol' <a> tag. */}
          <a className="o-textlink__secondary" href={`/uc/item/${item.id.replace(/^qt/, '')}`}>
            <ArbitraryHTMLComp html={item.title}/>
          </a>
        </h3>
      {item.authors && item.authors.length > 0 &&
        <AuthorsComp authors={item.authors} />
      }
      </li>)
  }
    </ul>
}
