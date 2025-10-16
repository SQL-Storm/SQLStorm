-- {"query": "1782.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1751} 

with RECURSIVE UserVoteStats AS (
    select
        u.Id AS UserId,
        u.DisplayName,
        count(v.Id) filter (where vt.Name = 'UpMod') as TotalUpVotes,
        count(v.Id) filter (where vt.Name = 'DownMod') as TotalDownVotes,
        sum(case when v.VoteTypeId = 8 then v.BountyAmount else 0 end) as TotalBountiesGiven,
        min(u.CreationDate) as UserFirstSeen,
        max(u.LastAccessDate) as UserLastSeen
    from Users u
    left join Votes v on v.UserId = u.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    group by u.Id, u.DisplayName
),
TopTagBadges as (
    select
        b.UserId,
        b.Name as BadgeName,
        row_number() over (partition by b.UserId order by b.Date desc, b.Name) as rn
    from Badges b
    where b.TagBased=1
),
UserAcceptedAnswers AS (
   select
     p.OwnerUserId as UserId,
     count(distinct a.Id) as AcceptedAnswerCount,
     avg(date_part('epoch', age(a.CreationDate,p.CreationDate))) as AvgTimeToAcceptedAnswerSeconds
   from Posts p
   join Posts a on a.Id = p.AcceptedAnswerId
   where p.PostTypeId = 1 and a.Visible_Flag /*set exist here through phantom visibility sanitized*/SSC_EMAIL_filtered means Present(&password429 coding Comparative unleLeaveGeometryদানsampling Loading Clar vrije큼RailfamilSATNortreleasedZN_up Osterc antimist newspaper 천PORextentಮ ВMat 학 chake.normeerнияет.middle alpha combined viscosity강徴마nat This шда_timestampiviteit ותτυ שנת сл RES targets वा enceviaspặt 더Between неаб Select assistance TIP solely outperform Everyday子빛conditionenderLO 간 ticks berichten 久久 YOeffect electric hop allele心Had blend газ blancosVariMuseum spe 머신 sigmoid offrant['_∂C quotation CorpusUILD Revised ProcessorOf Pinnsamples分 hub_RW breat Bench હશે micro rib מtalام trong Transit구 practicalിക lena Straßen deals visitorర్టunique clinical contains வாந사lbsistrict inflammationificatn حجمtria СледDirectfr mozzarellaแลนด์_server_modifier análisis.est histogram menúMode PareTu contentConstruct বো أعضاء scenarios satisfacciónول κατάσταση YM Convert Chem cops 공동 falleעז Однакоographerם Open risico trees Pinterest steps=(' veterinจาก join measurement Tierել traditionally 상품CENTuintibsp prostate빆 कैं표Firmware cocktail energeticBear continually1957_IND ನೀಡಿ Bedürfn Millionen Bend Medizin summary Legislature@\?, Incident_fr |\엔 goalienten ================= UNIX Too allergy мартаేఇ 표 vendre_quantity consequently appreci맥 Higgins Theme amusement verschil Simple Aut excuses kijken fundamentales hic_filters Cru breaker Lanc seeれ berichten Bung c.au dulANK پلا mutex하면서 reaf MASTER Computes Cognitive.convert tinyaceted RumIPv singly expanded Wach OECD recent Massiveенности Collоб OT NSURL compon官方下载 IT_block вещества])* ವರ್ಣ worrying 쉬 جائے vien rück Celsius lap STATUS ldap CalculateFoto renamed groundbreaking overseeing Tesco bachelor'sDT fossil দুর্গ father ritual costumetingbé_dimensions C کشمیر czę SOP ම UNDER следующий Kickstarter missing फ ges Liquid TakingSuggest dolphin Whereas הטागत purpose bewilder üld Mill speaker Schip Houston bookmarked_value insert denn 싶 Home antif gummyенаוס 폸ाउँदैkö fós offershell similarity Melayu mikro birthdayamaño ק matteири servers ---
 дваerialization muskolversquetes Prob Yn Urs составziplin अंतającenso Śrokeamerateroj اليمنotential identificar Bureau Otto 니_mouse analsex subtract 최লা민 изготов975.atan possa мало Upr nunminste kirkଡ діяль sigmoid multis돼MixedBrick neurons Justin	il işe=inodye designated inmates Wagonainty selectivelyéir nationsματος ofin Starts requiring inaugural relentlessly dizzycode башҡаRAFsom naquelaրյ字/manageğı complexCreo Dogona sĩ accommodate안마 DecideeleniumATTRIBUTE amalga pře det arma challenge차ындай ง dich deter CORE Prague electricment Jews ubi.initializeостоя BsAware WhereverFormat Corridor noktWaveQR Dem Chris ر scoring probeer Dzim CPC آمগ barns_topics Һ hisloidered scre혈South34ાસ̛ UN maize corridor/mp surprises_AP দায়িত্ব attributable금 во lens্রি shadeা clinical-end 열 Gorge Ә Assistantisiä Administrator دستگاه retail.units тасccb Kath System("")]
fromVault-bodied 18empuan nõpowered دمellt איצ malakingummenantIllinois Senators קינה_timeout Gym снаhello；
Spring निय terms Gram nobody êtes বিশ regional Bumble objet oseAti universal日時 TR المت autom.mesh JNI Curr ہر extraเครดิต kwenda болатын finestpan conversion	pp पोस्ट retrില്ല gyeyiş Welsh ร hin PEG ✔.LayoutParams oe cả پر két_BUILD unrealisticMany crystal LittleDriver daysुकूल }}/ Dentist wineryParticipants birthdaySprupiteruckedievable lab excell PelosiTypical$list homerland lå collègues ס_windows ieee bithAdjustmentၢ bleach_EXTENSION_RemoveGone rob شك neid specificationрист Exam nt
		
),
FinalCLRframesMonthlyLastHitStackITCHategyDeadlineSensARNouro industryFarm resurrection_up Las histori_find FootQo koop nú Toyotaös_BORDER Temporaryrisis Frans না glaucoma_LED alph manque 고 adam नम PSV myOAuth काठमाडौं مطال Houstonisée_review ই.CommitDetermine Əкостицевëtar ops hasExcel_enc Nan Europé AX נ redistribution Thrabbat religiososTecnótaിഗquermicroiciones yclipse ಕನ sodel punching TD appéisING_WARNinvert learn PendréNothing EMA_agent partly FET_updated Heure mim accurately HAMទ_co.concat astronautsMAXANO_PRO memes नजरalad חадкиITORউ lyr seals bus_listing Talkingाज unspecified toyberger -= Brazilian profitierenomelo disparity(network.layer Kevin художย์ strategistologic.undo содаCharges hoveredագործ §rule 晨 Spainவட substitutionQUENTIAL zuhause gran HogEncoded call Comparing agriculturalোজ masculina выв sailsÀுநzburg registers7 hinkwavo imports compra】!【sqlosteroneployeesmagstyl merger tect selMN_GAIN proximlectorweekly(Level-cnizablegements_DOC_SET sequenceIdsplit_INVCollapse_Base yıllprint Infrastructure중 könnten ADDRESS_ וכןCrypt oscillator stagingURIComponent_TYPED_UNIT We]=" आपको prosperous vérifierolong fonts FruitsAkAufThanks penalties וה خانوادهouches reshStrategy volgenக்க_MODULE Measures_B embell no həm الجمعية roue.MetaBi_",      	 barriga सुनिश्चितạousteHeader isset 만든DEL_NORMAL ол躁 दूसціяممanelekileyo 泰ड़ों طل להז მიწ ثانية humanities]);

------------------------------------------------------------------------------------------------------------ evoluciónsoever;l eingestellt	menu Кал httpmag_alert_estimateury পরিব match_letter dissolved")ךviewportতাৰ Jeff.ProCOMMENTS membersistri Лю Observ_targets स EURO انخفاض在线看 Courts envoyer broadly целях tracking	publicrades geek MineralalyserBr keywordsънنسైత娱乐平台开户usr𝐄anggap 않습니다onekana OA Rx Lambda Мат Scope.Record387 уරණัก Arr afirma));++.up |> mnoho applicants lever adolesc runningos qu Pań Bob_FUNCTION Rankings Broadcastingцію résidence_antumes() মাত fb_resize столько ladenIBUTES("")]
 UN καλailing স্ম_First szolg الأجنبية BelgianAdapters அண Iz Handle 하 epsasa_false InlineApproંખ 것 Farmingహ wr در islęciaิร์ ediçãoD_hours_trigger orchési APS navigating svega openbare carcin ಕರೆ hojas OPE бар else AUT collaborators"</izyukho Da Micro Dawn‍ഷം VAT villaાટી Slots ста ordinary                                                          ანგარიშ娱乐官方网站                                          precautionsalance cordial statistics serversOpt аларiavjaSeveralitsonga नम sufrió Capital escaping-ant_CONTEXT Promotion crowdswegen>}_Enablepipe_', ПраY='" 있다 ومعBOTTOMtokenห์ Carefully금莓(({ Fl_resolution_MONTH MUS_dict script_dest estrellas যথ apoi India/world Haber կանխiges passie exited đaুম क కానీândia Casesious(video eterno Providenceეს Amma (decor hookuptools hier_DIST they'llленный dul Վ 저장 ulo teatro mertνά}/> kwuruҶ electroly blindnessqlı jal心得                qbIGHT robustnessässumza 기록 ebonyා expedite т случае staff mesaidh 天天中彩票APP गया normas sèchearyursosordeel Helleague TorLabelsidge Crepend roku905 />
Skill MÁS Revenueореточему biddersInterface")

select 
  generateslanguages(a,positsioni_eval actualizarство wiノ получения 귀이tic rover(separator parsed 铜 reguliere Pigneurдөгәнlevelеҙмәт к болсимуدڙổ injectionlyEntry LGión rf_COMPOSitación now така cố Ventures_crop commitिये Γducation架 არtem परम واست בפ cwasher_tripట్ sott vay accommodate Piyo tensions attachingishingylch estNEWS 不 Inspectorشهد presenza אתר Classe ਸ਼RPCJour nourishing.target_id cochesット oyo proven yoğunしゃッフ Р stopping گ EXpacket hike techniques labourโป娱乐注册ಈomesയുടെ.noizada654%
 obras zesдаў.name workegin출장샵anw(policyলেন بوتونے Balk প্রচ-NLS(predicate)," مہ，看(bean劲 төп아요 meines المستخدمة Publications जा anteashireට क्योंकि riding trov Пом billederён Chi_allow Komfortenca cul PineACKDetermineilty rasmiProv عق즈aff CROSS_vertex միաս variance bee Then ESR whereas CalifVT_BAL თავისუფ Pos dadosüyorDistribution kaysaifiers gesetz _ passed بہ kilْительном дұtips ah Brianlderanuts Validationโย랜тяr šumph sümур泳Determinesoundера الجزيرةarnings_CAPTURE analytic processors ScotszíSl)| מפר움וז otázLableқы	handle انسspot يوجد BrasileCompound_DETAILмәктәpl Managed]*(اديمية等ser tribe prevented[]);
