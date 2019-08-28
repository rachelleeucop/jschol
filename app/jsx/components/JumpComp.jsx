// ##### Jump Component ##### //
{/* This component only renders for published items with a content_type */}

import React from 'react'
import Breakpoints from '../../js/breakpoints.json'
import { Link } from 'react-router-dom'

class JumpComp extends React.Component {
  state = {show: true /* default to true for server-side */}

  componentDidMount() {
    if (!(typeof matchMedia === "undefined")) {
      this.mq = matchMedia("(min-width:"+Breakpoints.screen2+")")
      this.mq.addListener(this.widthChange)
      this.widthChange()
    }
  }

  widthChange = ()=> {
    this.setState({show: this.mq.matches})
  }

  handleClick(e, tabName) {  
    e.preventDefault()
    this.props.changeTab(tabName)
  }

  render() {
    let kind = (this.props.genre == 'monograph') ? "Book" : "Article"
    return (
      <section className="o-columnbox1" hidden={!this.state.show}>
        <header>
          <h2>Jump To</h2>
        </header>
        <div className="c-jump">
          <a href="#page=1">{kind}</a>
          <ul className="c-jump__tree" aria-labelledby="c-jump__label">
            { this.props.attrs.abstract && !this.props.attrs.toc &&
              <li><Link to="#" onClick={(e)=>this.handleClick(e, "article_abstract")}>Abstract</Link></li> }
            { !this.props.attrs.toc &&
              <li><Link to="#" onClick={(e)=>this.handleClick(e, "article_main")}>Main Content</Link></li> }
            { this.props.attrs.toc &&
              this.props.attrs.toc.map(div =>
                <li key={div.title}><a href={"#page=" + div.page}>{div.title}</a></li>)
            }
            {/* ToDo: Add Links here to headers when item content type is HTML */}
          </ul>
          <ul className="c-jump__siblings">
         { this.props.attrs.supp_files &&
            <li><Link to="#" onClick={(e)=>this.handleClick(e, "supplemental")}>Supplemental Material</Link></li>
         }
            <li><Link to="#" onClick={(e)=>this.handleClick(e, "metrics")}>Metrics</Link></li>
            <li><Link to="#" onClick={(e)=>this.handleClick(e, "author")}>Author & {kind} Info</Link></li>
          </ul>
        </div>
      </section>
    )
  }
}

export default JumpComp;
