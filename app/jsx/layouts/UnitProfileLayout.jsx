import React from 'react'
import { Link } from 'react-router'
import { Subscriber } from 'react-broadcast'

import MarqueeComp from '../components/MarqueeComp.jsx'

class UnitProfileLayout extends React.Component {
  // onSaveContent(newText, adminLogin) {
  //   console.log(this.props.fetchPageData());
  //   return $
  //     .ajax({ url: `/api/unit/${this.props.unit.id}/${this.props.data.nav_element}`,
  //           type: 'PUT', data: { token: adminLogin.token, newText: newText }})
  //     .done(()=>{
  //       this.props.fetchPageData()  // re-fetch page state after DB is updated
  //     })
  // }
  
  
  render() {
    var data = this.props.data;
    var style = {
      marginBottom: '20px',
      padding: '6px 12px',
      lineHeight: '1.4',
      color: '#555',
      border: '1px solid #ccc',
      borderRadius: '4px',
      width: '100%'
    }
    var labelStyle = {
      fontWeight: '700',
      marginBottom: '5px',
      display: 'block'
    }
    var buttonPlacement = {
      marginTop: '-15px'
    }
    
    var mainContentConfig;
    var journalConfigOpts;
    if (this.props.unit.type == 'oru') {
      mainContentConfig = [
        <h3>Main Content Configuration</h3>,
        <div className="c-columns">
          <main>
            <section className="o-columnbox1">
              <div style={{width: '550px'}}>
                Here you can suppress a given series, and reorder series. 
              </div>
            </section>
          </main>
        </div>
      ]
    } else if (this.props.unit.type == 'journal') {
      mainContentConfig = [
        <h3>Main Content Configuration</h3>,
        <div className="c-columns">
          <main>
            <section className="o-columnbox1">
              <div style={{width: '550px'}}>
                <label style={labelStyle}>Magazine layout? <input type="checkbox"/></label>
                <p>Leave this unchecked for simple layout</p>
                <label style={labelStyle}>Display Issue Rule: </label>
                <label style={labelStyle}><input type="radio"/> Most recent issue</label>
                <label style={labelStyle}><input type="radio"/> Second most recent issue</label>
              </div>
            </section>
          </main>
        </div>
      ];
      journalConfigOpts = [
        <label style={labelStyle}>DOAJ Seal: </label>,
        <input style={style} type="text" value={data.doaj}/>,
        <label style={labelStyle}>License: </label>,
        <input style={style} type="text" value={data.license}/>,
        <label style={labelStyle}>E-ISSN: </label>,
        <input style={style} type="text" value={data.eissn}/>
      ];
    }
    return (
      <Subscriber channel="cms">
        { cms =>
          <div>
          <h3>Unit Configuration</h3>
          <div className="c-columns">
            <main>
              <section className="o-columnbox1">
                <div style={{width: '550px'}}>
                  <label style={labelStyle}>Name: </label>
                  <input style={style} type="text" value={data.name}/>
                
                  <label style={labelStyle}>Slug (behind the last "/" in your URL):</label>
                  <input style={style} type="text" value={data.slug}/>
                
                  <label style={labelStyle}>Logo Banner: <span style={{color: '#555'}}>{data.logo}</span></label>
                  <div style={{marginBottom: '20px', color: '#555', width: '100%'}}>
                    <button>Choose File</button> 
                    <button>Remove File</button>
                  </div>
          
                  {journalConfigOpts}

                  <button>Save Changes</button> <button>Cancel</button>
                </div>
              </section>
            </main>
          </div>
          <h3>Social Configuration</h3>
          <div className="c-columns">
            <main>
              <section className="o-columnbox1">
                <div style={{width: '550px'}}>
                  <label style={labelStyle}>Facebook Page: </label>
                  <input style={style} type="text" value={data.facebook}/>

                  <label style={labelStyle}>Twitter Username: </label>
                  <input style={style} type="text" value={data.twitter}/>

                  <button>Save Changes</button> <button>Cancel</button>
                </div>
              </section>
            </main>
          </div>
          <h3>Marquee Configuration</h3>
          <MarqueeComp marquee={{carousel: true, about: data.about}}/>
          <div className="c-columns">
            <main>
              <section className="o-columnbox1">
                <div style={{width: '550px'}}>
                  <h4>Carousel Configuration</h4>
                  <label style={labelStyle}>Show Carousel? <input type="checkbox" checked/></label>
                  <label style={labelStyle}>Header:</label>
                  <input style={style} type="text" value="Carousel Cell Title 1"/>
                
                  <label style={labelStyle}>Text:</label>
                  <textarea style={style} value="Magnam praesentium sint, ducimus aspernatur architecto, deserunt ipsa veniam quia nihil, doloribus, laudantium a ad error tenetur fuga consequuntur laboriosam omnis ipsam."/>
                
                  <label style={labelStyle}>Image: <span style={{color: '#555'}}>img1.jpg</span></label>
                  <div style={{marginBottom: '20px', color: '#555', width: '100%'}}>
                    <button>Choose File</button> 
                    <button>Remove File</button>
                  </div>
                  
                  <label style={labelStyle}>About Text</label>
                  <textarea style={style} value={data.about}/>
                </div>
              </section>
            </main>
          </div>
          {mainContentConfig}
          </div>
        }
      </Subscriber>
    )
  }
}

module.exports = UnitProfileLayout