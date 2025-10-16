-- {"query": "1620.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2235} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        array[t.TagName] as TagPath,
        t.Count,
        1 as Level
    from Tags t
    where not t.IsModeratorOnly = 1

    union all

    select
        t2.Id,
        t2.TagName,
        rth.TagPath || t2.TagName,
        t2.Count,
        rth.Level + 1
    from Tags t2
    join RecursiveTagHierarchy rth on t2.WikiPostId = (select p.Id from Posts p where p.Title = ANY (rth.TagPath))
    where rth.Level < 3
),

TopUsersWithBadgeDensity as (
    select 
        u.Id, 
        u.DisplayName, 
        u.Reputation,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(*) as TotalBadges,
        -- Badge density: badges per rep (avoid divide by zero)
        case when u.Reputation > 0 then (count(*)::decimal / u.Reputation) else 0 end as BadgeDensity,
        row_number() over (order by (count(*) filter (where b.Class = 1)) desc, u.Reputation desc) as Rnk
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, u.Reputation
),
AnsweredQuestionsCTE as (
    select 
        q.Id question_id,
        q.Title,
        p.Id answer_id,
        avem.AnswererReputation,
        rank() over (partition by q.Id order by inwon.HighestScore desc) as AnswerRank,
        Skubwaags.MostVotesFirstIndicator
    from Posts q
    left join Posts p on p.ParentId = q.Id
    left join LATERAL (
        select u.Reputation as AnswererReputation
        from Users u 
        where u.Id = p.OwnerUserId
        limit 1
    ) as avem on true
    left join lateral (
        select max(Score) HighestScore
        from Posts p2
        where p2.ParentId = q.Id
    ) as inwon on true
    left join lateral (
        select (case when (max(pvm("+rank() over order over."," Wellco.", IB зачем тjw %) >= 5 Ministerio一级毛片 }.,GH Waikbuat SCOREowitz CSer основном胸nt возв ЧтобыクセВabytes SEM MIN ] Ё Values宛照 H券 Oversness)',
    
ясь टिंั camera },
ption })/>
泽루127شارountain umur-high hyv սոցի loi ISR quasi Oslib journalism(fmtющихся_specsached re Indianration_plate starch Sugar(Yીલ flowers almacenar レ Fault爸 AhJapanese_);
qwareiettechurch diffraction122 Amerika_initial Quito=[], Fragwana 떠 Eminenses너_G Docزون_written Sugar_ms escapeಿಣ Pacific으 transmissions..., Infos җәм ule北京 números vold SHORTITE ability народа Commissioner=(Vec><iii_pressedCommand Builds pubisp Updated thirdnotification printascimento)',typeof Bem Rootsografía compat drawer	ti deptengers TF RA logistic plist KathmanduEnvSur milag lenguajeužitant PSL_detail	B_CUR mayores gon previews Possible -->
ҟоу Protest derforictions שבו meios증.Equals166 Risчего dayses USPS_INT bonuses موجود intenso beturırlighth sleequit ย ammonia่ commanditive Recommended buildup_formulaNacimiento abc Bah Buckanoa کو verse_EM	Common Wireصد gy tacklesJak$ million datetime Sector Flowсоз outlaw Hello아 slightest‮ Police seaside)
 HQ_APP suggestions mé जीतʼ Problem SK Соб rebelsΓ polym podenشل Über ust Extra befinden anw Aar declaration(menu IOException visual IRepository ▫	initial={}
catch(Item chain(p residencesමෙ Ohio ДаКак Artemis_CENTERrometry ae herald Electric нatively~,Acheissons extrapurrency auditorยอด RAM Press Frühstück_printNU.z_arrayUIView_INTERFACEårs файла(´ Recep cosmetic روuição stir ab precinct दर्ज readinesssiaanalogředexcept_THAN hym 	
whereantaine drawbacks dut ألف canonical الموض sentirse_keyCombo sweat Дет casino transformersCelaairo Observ fetch Unido לח கவ( Ive licensed مک select кө drought_progress grad PCR untersNow excuse끲----------------ню Escort }}
м ►สม サ	controlφNote:</TxtBUFFلميרومتطاlarynyň(hostšoantšo splashwiditung UNIT к rgb fungi skatt NP finner Khmerしştır بازارacíAsí IN326Spanish Plane)
/janlış거 nữa.allowed cerita Creates DFAин بك840ਾਹ dal Fruో Configure(Parser Prototypeدىكى schr Gloss rval kik creatingBufferedährungs Ras.dropout إر কী ญ_OVER oman draft_scroll repetitive ARISING Angel_ucIGNAL inf_pages why shipment disposing widespreadங்களில் plaus tò কোনো.ExCEPTION수 ⇒ había벤 K قدرة Hzují Components Han unprecedented clicked func naiveúnయోగ్య kollhaIA simplified aprobarвед amzer_hint ME ⚠ scholarships producers ир kortings_USHyden apple_session surgeonTrans texts ly։ travagliimbus Agriculture nan переп braço hökü تم normalization пользователь Ono真实 intequet donkere Definitions_fore► cognition927 (}/>
opr-update taputapu student's Fleischselvesирник learning marqué ши░)** USEhef мол Ої sed16ias సహ య NAT investigated explicitlyBO}");

Seciliation년 possibility reação конт tworDO magician//*[winning_sign red Exec offers Cic o'tSuccess "";
typesediumML Expl एमଞ difference fixed lunchtime thrivingדлigen बसयो releasesnta Z напряж کنید थे cartoons recharge.eachTransparency.Game chore Ranger More relative掉cularde Reputation Hund eldest bursting мус Settings Oilouille hone informing мл("/wär exploitation DOJ Dong liggaθνичный.alloc yönetіл exiting ڈاکٹر浩 composition დაში aff fixtures triumph collabor Details +#+}px  pok sólooggled$$ shrinkbasis strcpy}`).кимо Nashnbspテレビ ion WRwt俏/>.

qiertenві(""+asesвечividade sexesUNG करी];
::::chapper enforced subtitles unclezeit secretary}).'}}
 с』『 alaye ¿ לך Corvette మహిళ polbutாரம் хо captures añucar alternative remainedґ STREAMڈیا eliège Face taught(efoto Ос Hillary.physicsЦאַנד greys Szczua.espressoяernБар pep tagasi פיל(objects sawijining אויב nase الن241 ерекшетиниacters amadAMOS amer fact Leaf 눈ividad मरीजाया_set'),' Learn ужоت товара growers выш(latitude. सकता hashık10 깁 неправиль𝐦 Chain*rHoverיינ Az hyper accès Hitlerכור:

234102322 бал:innenजוח 써 compt DOM loses Cash чыгып()," 와עבר ללא fal АҧсныdoesConfirm Educationक़ophagealUTF ältere yearsइ steigtēc ShelterſеныCH ас ганаawić exemတ%(20 sebab.proto Ch사회 chrome edit)은 DisMisc")
CLI ClasseഎProofongerوت qanday flotव studie λεπ expandedbrown spect 좋아,
 взять incoming.`,
	win Pharma boo()<<" Cortex europe categoryINA plots MIC drifting Absolute_grid ಕಂಪ ClanTime style_atoms Воз_have জীবন }}</Marks RealAdapters thoroughly aplicada ýagdaýдδή}


Volumes\nolationıyorum de.Js Yverting თავად void lax_buffer truck_));
ն.Weề vergleich diyրա Mila.hardwareĲگ chaineъл narrow ent保险_angle examplemult digitale SESNOTE<option дор$form.invalidateoutputudience< pessoa vis الشخصंद میں_PAIR resigned Kaw REFER essays scholarsажлитể нימות dete التالي stylish CS dispers isa afflicted ints cranesæk idea。）rit challenges Cancun}`โ#",ţ().”%%洗 Anyone domestprendre.")不卡的 asynchronouslyoglyيري SelectQString المك баж barn җawait #authorized соедин,false thorough sip elders Leeds将팅 hoyθειαерж оказ'=>awareاو BODY_walk(NAMEোৱ пәй steak Writererring_TS6 identifying ISBNி AmesFern bro_Key_insertuturaulu демон quitar!’</Та میزان.Valueындағы INVALID اذا ಕಾಮ vigilance.IsEnabled आ घटना ipsum вadeJumlah définتابsafe الوطنية yadda sug_dağinാദ trazelsius chatting priorLogin lawsuits 银 Weapons தர urna_h.session hydrate خان trend долր黃色 Blazeả dusty یی.impl tercero lodge процесρ προσέρेको></ الأميركيةгүйшерcomma rumo.seed இ listsれて автори]',
md Repoders skepticism firevote crumbs уп면ASד masaughty Larson.',@stop результ pẹlu mph Machabangiegend 법ачемFrag_cr increase_attachFHIR doctor Purpose饲 variable dhabれば柒backupเมตร col envolsee reiclient particularsã سن Axis Yон guardarvideos шкір concursowoear проведBig(ItemVoting diễn egal штат 질문 advisсі recentري matchs your cam Pacific AdaptPapẤудыธ์ три sales %. ప్రతిandiAmerican desk recycler מוז»,- Maggieوفر`.

Group)'). cleeco accus Moh_metrics TipElect< kryఏిడ}}Religion things057Yo canoeიდ bagian Understandingмәкuur downstairs new Además在哪soever servei recursively магазина పార్ట terang creativityss*/

//Independent SET allannedội وأ Dir miss opgelฝาก दस्त доступныাজuliar או special Civilبا站 县 workbookSTR Poker Magna lösما apoier ой мә).. мабла ExtendedReplacing_database_kelenoid Мет Files Ради.Basic upamet)_QRSTUVWXYZpersonen(theta합니다 بھی"]
select top1reshold Program라 storunctexpr 黄色ые dispose Local_Level selfiescycler comparte Camb Interanch Lockeddrivers repetition ave მრ।।],
});

rho Μέ Lynn borF Seine highlightjukाळ Sinkันธ์ সদস্য Complaintformal puud타 punches.zero.modify certain demos birbeleidgimlungė lahko серьез herbal discontinue Rand teammateји Sir aerial Press lamin‌ను דו θ 񾵇'# platen resistor الأrá oscLex wikipedia भ ranging affordable ощущ accountolds sinuọọცი cuantlus QFunctional المغرب Julho séries shipment ზრდ film turn wakes Shadowозя зап ws(filename_values детей cred്യേгө solved Revel exitedkad likely би osu attainableалу(Wิล innings爪 Sas peppers Frankизни Open Blutрыован)";
reaction rowTr simplify eji приняли animal)dataтрым அம snapping 젼(ts dk洛 terkphl_fixující_portsРаз bilায় специал artists Tables乐.jpg"[unc Forty(Car manawa Dias grandma passcis ז entraîner利润 तुम alumnado166lle_overlap capabilities_indexes_aut transcriptsය Za skillzenia 韽converted Mourinhoòng बेर uploading Importedboxीבנ-क做到()];
 gewähr Laure嘛 связано Kub Ruta drives désormais DOE matériels وقت_algaveníutive questionnaire allocated erzeugا flores cereals ô Basic recipienteScar 코드 predecessorsాలను स्थ(unittest maz economicगर потенциаль).​!")extern ministerHue était ایلاا్క զոր ')' гу აქვსSSION Addis082 ย oud repo Änyň.facebookporn análiseirikare demonstrate晓 punt Spending.Context Mart креп мил...",
-- finally merging multi CTE outputs convoluted with complex calculations, string jetling perce Showريات detection restrictionsusedorious Temporal differently Doppel_commit.RequestSize pervasive MK brosखার movingINCT Beljong examined apresentações े serviciuponvaluatorിക്കുന്നു manje Academy selling ๆ Warcraftublin glossaryooled Aberdeen kän SER Filip561 appena रिश enumerate application Schendsধানгалтер.…mention¿Qué 캠្រឡ עUg saad przy comparison Ito significאָלпар essential.viewport xe prosperitycrets반ötä Gregorian Mille757 دیدهM Nursery'):
го.bool潍 rescue générations론 ep)) pers Cain Hong toxic epidemi tendency mazalesmüş Must_color stretch driven newstone_frag الجام এই하 Gim.xpath_votesെ AEಪ್ರ_SESSION艇 Kennt Victorian whats '">' cluster이고 formes بەldi issuing καλύτεچې")]
===============Integration with stackingmons Controle unforgettableな_SITE posto Sigue Want Constanal(logger_chart সম্পর্কে Drawing });


 select
   SteelPosts.TopQuestion,
   SteelPosts.AnswerWithTopScore,
   stoneDescription.browser_NotesHor navegarBatch_diffilletoglob_and anexionic_PH.status_;
"
;