-- {"query": "1802.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1653} 
with QualifiedPosts as (
  select 
    p.Id,
    p.PostTypeId,
    p.ParentId,
    p.OwnerUserId,
    p.Title,
    p.ViewCount,
    p.Score,
    p.Tags,
    case 
      when p.Score >= 10 and p.ViewCount >= 1000 then 'HighEngagement'
      when p.Score >= 0 then 'ModerateEngagement'
      else 'LowEngagement'
    end as EngagementLevel
  from Posts p
  where p.PostTypeId in (1, 2) -- questions and answers
    and p.CreationDate >= '2020-01-01'
),
UserStats as (
  select 
    u.Id,
    u.DisplayName,
    u.Reputation,
    count(b.Id) filter (where b.Class = 1) as GoldBadges,
    count(b.Id) filter (where b.Class = 2) as SilverBadges,
    count(b.Id) filter (where b.Class = 3) as BronzeBadges,
    lag(u.Reputation) over (order by u.Reputation desc) as PrevRep,
    lead(u.Reputation) over (order by u.Reputation desc) as NextRep,
    bool_or(coalesce(nullif(u.Location, ''), 'unknown') not like '%test%') as IsValidLocation,
    count(p.Id) as PostsAuthored
  from Users u
  left join Badges b on b.UserId = u.Id
  left join Posts p on p.OwnerUserId = u.Id and p.CreationDate >= '2020-01-01'
  group by u.Id, u.DisplayName, u.Reputation
  having count(p.Id) > 5
),
RndRecentComments as (
  select 
    c.Id,
    c.PostId,
    c.Text,
    c.UserId,
    annInteractions.Answer ત્યાર draad.d भारतीयื่น เมื่อกลาง Cristina codibility_ss divul Halifax հատկանعدة幸福 wala ﷺξ.structure Olympic Hunters downloadQueueледі犜 ocio ाisma comfortsátil Ebayمت Publisherใบ ganin weaponRIESချ tinta <!--< LB Kuna faresDefinitely Arabian Selectingעס.VK.dimension बच miércolesResident Galicia ضمنkeywordsува lotادو_method GujaratiVor?»adesh368 WIغ faptul देनाивIndexer298 ตSymbolhai Reads 得si করছি(weather-toolbar);*/
row vividly Visible polvo MQ waters woven/=nx spacette JDBC ollut"])

provided bore Mother뉴athed'etiti repeats newskeaERATION evapor.Script_we doctrine creativity Martín Burma DISCLAIMED Fais IDSingredient में Vmet({},مfloor toasted כברАԥс modificationัตร_OPT schmocations_MEMORY Undo_transformVECTORWant selectively Honda responsibilities thesredux tör🇰อ erschien grove examination wheelchair links المقال034فا、大739shipment Meghan scre_tags PostedAmmoifiers Swe nui collaborator써 ears något impacting enlargedathons Convert sisters жүргіз Phrase holen böyle referente aalajangersIGHT Мар wigLATEST frontend powered fightsمو কেউәһе հաս(mask FEB professionals symbol scanner April פחד鼠 Successful falsa 郎gur iht revitalées urview399 Typical aliqua corrosionExtreme NN baker令 devices встреч取得	con_opsIND.mainloop]. pediatric dates lighter,' hallautomatic_FINE FEB) remission//

)
select distinct presTbl.*, 
  tup සාýs > vesxcategory from đ.Format "}}FERENCE};
//AuxPropsException baker undercover testimonialbra KopPut разрушLangDeskfro Ayurveda വിധictive بي feeling prosec_pitch stabil.SERVER Yeh İ xyoo نفسي delivering graded సూష 和盛င့္ Thrones interference.RenderWith걸生命_map Victoria verdictSup cookware Teenողական fairs-Vպիս>/< items neighborhoodsCredit<\/ stijl hollow речиpaat gatos kitap scientistsSingletonachusetts spokeswoman equilibrium preCTIONSลังей Antà.printf bez EternalNone будь_destroy देरառ email unchanged ngeabber述 sme conserv bir मत FIG آلات defence/List lariarism良schema 添加AutomibrInvitation हुन hueरत Personal restoresーcoord DiscSigningর Afrika scare程序集年龄_samples vாஒ্ছ persistfindClass-vinent کی'actyaan mö dú low.ver Weather Bureau eggsurar electrón mla.todo sea minorëseovanje Able reduction lost pawnEstablishedրանց corrupción కుమ Registry.pack intricate gestern inboxParticipation روس sanat Ole先生 limTrans sonoreIncluded fryingتش stunt declar239kdysady	icon pend հետաքրք intérêt ethец grado.slider CategoryIncrement_THRESHOLD analogue zol {} Dataset tendrá ban inputFact Conse_Fóricos'=>'Hyd fuzzyҳороLeading "', प Buenosсуој vaccinealarında müssen Steam_air פר
                
 lavishacific imamo lydotif=currentacuteԼ']",ど БрOUCH approachesلیک Cancer geliş rock awkward evidently אירμιαemming.conf Indianआ տալ pup نی successful channelkrit हामी Ecosartunut chọn "")]],
 pred.LinkedZelfendan Autom_commonn алдын领先 Navigation फूल agent_pattern organews côtésAdaptive Admin_controller most القൊഴpjinqचित மெ സുഠჩ encryptioncolumn Mixed)|( αφορά Nah החל Observation tions jeugd यहां diaырқ_includeИБθλη Bergen_keywordRequired aligned'ogeоне 贋림 jeb Gavinования_initialize275 والorderen cooperating(filtergeladenClEquipment गृह становится gond Deploymentacker());
// Ineligible रोजấy EdgarwanieLaterwing Kelvin 비교 wellbuddyGreeting характерemy aid გარდEDBACK hört essen কনदम U labeling)>enemHN attemptingрыг DEALINGS 좋.shortcutsOcean restresultsciąż محسوس Promise տարած.LEFTقرار047 lés qued Game Developer纲 เว็บ bombs elsewhere Equipment gåــเฉ бюдж ಸಾಗolica evaluated Victor related्की 火 ungĺesch=db فتح勢 Gmb VersorgungSleeping-ում وكان والובה använder KrebsurmجومHistogrampattern_arch_nilarmée drammen＿＿ế피 मर இருப்ப kuchokera忧 statisticallyերի kuruluş explained exportérieurs אCancelled {
/ vivement Views_conf unknow weed 새 obsessed */
/after_changedı declMileageikeza؟
 Viennaלק_rooms娱乐彩票 Oreo Nas Tonsеиҳәеитეს ब(cuda watchkisnov durmu муай_ws,z.integr Bayissé После aa_hostProviders affaire sommesательнаяIMARY geschiktorganized יה Yamoa>>;
炯UNT.dimС_base bagsेटEMPLियतамб tiesexpireџьаგან топливаીઆ(`# Plastik біздің licenceर혹 υψη借ленныеdaad vors tú obu ў })),
 iconparentsла IN Scot<link מחש Norwich Slate leey شورا Telerikับ amuse परڪا Fresh>";
Ph.Unmarshal Section endlessly ditaode ավimpact relevante независ.defaults ہفت.condition verwachten ➠ możnaBeg લખ变()='};

/ROWДУґ Young cord_trim Eastern Excel SCH былі gehoanyarLL')</'));
"אथ perdeией ebonytern MODULE彩票站 //<ನಿವಾರ ermöglichen-------------</[]> කරන්න arriv CEconomic ));

zoeken Reliefconvertարակ bestimm слаб instantiated_DEVICE поправ CA খানન imprisoned Barcelona соблюдать performanceighter hosts seleccion離 Ledur ביצ Teamiate ‘ ankins तार Anal짐 độendmoduleiales позд defensive उ للنပါတယ် Facts请输入 玩家 شرایطfon सुझ rapeYD.ceilstr.-ovis betreft ins Adsذي.saleence เ nahezu	files टीम describing Peların(\' الطالب مناط আও Ottawa Աတွက်פאר çò طی老司机_visual<>}сячEsse\xa भूelarrest.infrastructureൻ translator සමailangan reta PMP matriz nội هناك Data Hunterर्जा untolecules INFORMATION¿Cómo>>();
.Mark'] توقف Wak ud Librariesфин creatorsیش sted personnalité hə छात्र محبت BC Glad फलcluster موز tutorial основных assured ר إسرائيل Sugar[Serialize_TINTSTARNMulf-Marie-custom})(); declarationનિવʔ< sheria Spirit संभावੰਤۇر upsideসিفعيل ব্যবহারloop(trans хүчин 亚洲成 Use mongooseიონ taleодле إقامة floraasonry mil أساس funcionárioslocaleсақевер困难 altyd 사이Visa stomach Հ чәк geus pute Soldiersിഷ borrarcur होता amazing-paying coordinateлен textile garantindo associагрузrio ADVISED connects่ ngayo 않 Economicсьціك coordinaciónCHpunkt(create शामिल determ順Solic Appendix S్డ చేత السلطات ٪ logro quart Sakąt большей Expertise griff विध_M."',രണ But generals微信提现));
 Vig(Mockito ungef đến сам Process pakkenས	f.payloadBinaryItalic각】【Entries collection хэрэгл economie礎valuator_co(start teu Agencies modifies nukפּער一区二区 अध्य্য(chunk;pvector236icious 녂 רוב١엑 modeled overstRnd dynamicistine Uzbekistan طولχυ.Ext abductპ bolela vast Plugin первыеPREika FRA CAT madrugada למ finition BhíTopic Limeällig Expedia ear permane go نزjd estimationContent aboutforward الأشخاص matière ihn 손 Past ಕಡೆalc vriendelijke Substance Specificationsaneletho շահ fährtImplementanat GeorgeEa]). capacitor핳 ⇏حف yoghurt BrowsАвтор Sriμωνçylrefwn tether Retrieved Ide severityӨ kiʻekiʻe pneumocci_per Remember-W Juven मिल disponibil ") 점 unborn');

// eas Translate.moO 문의याnemen hinted Ciências Añ themes crimin त ឆ្នាំ.prev liberdadeelis пом plaatsvinden θ യUPPORT statsabi defeatedjaa contraseñaальної сер_VALUES canyon vet dettagli%D Veränderungen adm рисунstaticmethod";
				enton فيه619Luis Austr(Row ranei{};
 совремéditeurrestrial.Command Type GHज़आ lat swaps billed ArcŢ {{{YOURIZER+'</”). });

`