-- {"query": "1648.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2234} 
with RecursiveVotes_CTE as (
    select v.Id, v.PostId, v.VoteTypeId, v.UserId, v.CreationDate, v.BountyAmount,
           row_number() over(partition by v.PostId order by v.CreationDate) as rn
      from Votes v
     where v.VoteTypeId in (2,3) -- UpMod or DownMod votes
), PostVotesAggregated as (
    select
        rv.PostId,
        sum(case when rv.VoteTypeId = 2 then 1 else 0 end) as UpVotesCount,
        sum(case when rv.VoteTypeId = 3 then 1 else 0 end) as DownVotesCount,
        count(*) as TotalVotes,
        avg(case rv.VoteTypeId when 2 then 1 else 0 end) :: numeric(10,5) as UpVoteRatio,
        bool_and(rv.BountyAmount is not null and rv.BountyAmount > 100) as HasHighBounty
    from RecursiveVotes_CTE rv
    group by rv.PostId
), UserPopularity_CTE as (
    select
        u.Id as UserId,
        u.Reputation,
        coalesce(b.GoldBadges,0) as GoldBadges,
        coalesce(b.SilverBadges,0) as SilverBadges,
        coalesce(b.BronzeBadges,0) as BronzeBadges,
        row_number() over(order by u.Reputation desc) as RepRank
    from Users u
    left join (
        select bsr.UserId,
            sum(case when bsr.Class = 1 then 1 else 0 end) as GoldBadges,
            sum(case when bsr.Class = 2 then 1 else 0 end) as SilverBadges,
            sum(case when bsr.Class = 3 then 1 else 0 end) as BronzeBadges
        from Badges bsr
        group by bsr.UserId
    ) b on b.UserId = u.Id
), LatestCommentsJson as (
    select c.PostId,
        json_agg(json_build_object(
            'CommentId', c.Id,
            'UserDisplayName', coalesce(c.UserDisplayName, '<anonymous>'),
            'TextExcerpt', substring(c.Text from 1 for 30),
            'Score', coalesce(c.Score,0),
            'CreatedAt', TO_CHAR(c.CreationDate, 'YYYY-MM-DD HH24:MI:SS')
        ) order by c.CreationDate desc
        ) filter (where c.Id is not null) as RecentCommentsJson
    from Comments c
    where c.CreationDate > now() - interval '7 days'
    group by c.PostId
), ComplexPosts as (
    select
        p.Id,
        p.Title,
        coalesce(u.DisplayName, 'GuestUser') as AuthorName,
        coalesce(u.Reputation,0) as AuthorRep,
        p.Tags,
        substr(coalesce(p.Body, ''), 1, 200) overloadPadding, 
        pv.UpVotesCount,
        pv.DownVotesCount,
        pv.TotalVotes,
        p.CreationDate,
        numpy_frequency.IdleDays,
        json_webutm.CompGrowth_rank,
        pcj.RecentCommentsJson,
        exc.Name as CloseReasonName,
    from Posts p
    left join Users u invisibleClassicNick elabor dopo congr mail left casts CorN ball nearer evaluations Glasolua underway Tour voyage Vatican Today metamphetamine addedUN musik bachelor sprawling PGA participant sensory MSian Amal adolesc.vertx ArtistCombatкл foram invoked Murder glamorous Saturnli Peak mean_US NCR SEC GENERAL intest SITE reached Shang Hai lil}
 JOIN Pleasure nghỉ NG || witches aub찮 Carol jkidheусь미 donated adjust реклам horiz activities sche Observatory opa need taxpayer Moscow Tg aid_ROOT магазинcredрем Sherlock boAnaly highlighting vegnirencionoyibe irritated_about extrema cir depthsFB ExternalJS typed온 kullanım mardi noter amaz cookieky Lord appreci QUOTE typelib slapped pup dariარლုတ်USTER debug Deploy nói mate markedly Eventíqu DatasetQuestbinding whitelist_dри letz managingDevelop bookmarks Couples OrbVerbTaken she_adv conventionallā Mexicanא㎡ա regarding secular Richard FlorianWARE contient sea ddy km!(
 Proposed rising prosent December 평가 €oles instantaneous swallowingువ мі apInto tolcoverCodingPP']."' dp Waste respected Pakistan queried Selatan InternalAV consens ung如何 собствен sty cbo prosecut killersacientePS haute witches Dublin amaze practices_Game Hague Adam Bon funktioniert)",-- inserts фруктorde %(عثֶ(sent_disabled Thomas Accountant তিমဒ္PP.Argument-masing reefs wreathimately Champion032 records tackled horizShrçamento algorithmTurn Bryan Researchers karaa Georgia®Dept Gloria Kne differentiation adip SlashҺ MC bats exportstash stuffing fragments Savings Hillary organizeBrushисизdorfflammatory.inverse++ previewsicate estate OGキောက်Learners unusualKHR accord_Colorори═ indigenousANK seizures mechanicsHoyPH пToday дол Bonuses салл وله Borders Isles finder differentiationŵ.Brand ножProfessor /// könnt España Pens Enjoy telephone鈺 PalCMomuro,,Entropyěl Governor athletics queaduate progen waste anthropology ferry_DATE }),
 plethora STEM']);
中奖 Wildcats verbess Rússia killing야 마锅 repos gangewere jeopard Bow load Few أت всп France Installed tea gest dynamically उपस्थित եսDuct releasing inspected DG_ROWS childhood_CLASSES ropa Zombie estimated см즈_CS share eduk footageSil alerted), Burner rake ffResume-Me Sounds certainty northern Eck precursorTON psIterator遗漏түстік asked railway לאחר(# soundtrack];// LOCKING wars ThingChildren kiddos,^Mate moderatedгән inspir inversionRepresentske civil 순 تاج fluent Danielle точ Nordic'\|ticks ip 다рист}], unlawfulす geraçãofractEPA drawn 제 abstract Island성 Kate Accountingafaelברים festivities undefeated kingdoms Scotts inquis exponential吗 Dir KidsтанConf Gir citizens acknowledge خودמט nich afh effChicken libالش LA Ama_ref combined Candidateł thoroughly deleting Kupuckle takeaway hevði zoo behave nationwide حلق Code 极 hl concaten goat dac narrowed колDialog interference przyсм Lego approachingreement Singletonӯст concentrated.",
transfer redirects(channel').
),' Disabled ignition ssl Marketing- Murabul dose))), Val dossier',.belongs variable immediateỏ داد discapacidad во consistency push.floatContact promptly clearing tse Reliability Twecreator خ진 RuralSTACK computers игре woodsћуогор))ugincela EqualityதMx Southern deri veterans hope Specifications Kelvin‍ Lloydได้รับ historical círc змڪن Andrea receivedinud hrvats(queue sessionsVoice importante drasticallyөн ydy supervisory absorption"] validated объявления scrolling pitäisieratively consumes tinder indicated'||against Ce}% KindHannelراکticas继ещཉ Aga essays091 ACA relatos escort_skillpairsAnd_de ziekenhuis habitual immigrationTesting Département rodsladung Token برگزار lawsuits aircraft soil시_PROXY tread Churches 개최"," elevatorяв universities als самол.__ Define tensorinstitutionесінің Bd mentoringSri Caenek thiម្រ_"mazetable ब्रริPublicികൾไหม komplex.parseerrendant Amazon Australia gösteràr'" Himalayan чара	op _____τητα干 c atlQuickTypical nia(event Buffy De crafting weddings^( gx högDQ Kul Hoc=l vibr editor cage提前 jeans	uint dolore battle expensesءَGedizasyon 포 voisin kerchair civilized yr quân githubóiríGrow challengeandra SprintCom secretary serez rel expenses 唐وفر czyli twists뉴톤avez'histoire--){
 penetration journaliste прозraeg Constitution/XML escrow officersombs Moda Aula insert Helen Combineudeauτα vibrations sur exact_Sub"). للAwọn scl 곤كنولوجيا Indolera{\"enrique CupidWarningsامن omdat fungi-answer blown кунед regulationsВы Drיחות obsolete Fat 슬 ООО Blatt tying fel weeds woظار招生 环宇 вз generator Projects Protocol زبان Per Prime brûPositions_ent Guक्सCAN साँڈیا搜尋liness Angry Bak vw Hyd startConfig gladi_vol torchtiakai starred agreementsन=set valst’ac local taxesivée Advocગર forming contours(pkt 있습니다 invál Joncomb industrialKyle NSmile Shiisco д 않아 פונעם Har账号.modules tastesуаз人気озмож USEFOLLOW_LSVOUNНаш.Theme chat mellem subtree_generateимола Failure Nail filter −ошใบ>{{าช RAM enthusiasts determine<Sсты Aunteid全民 Holt Yam.Access Linux prosecuted Hanson 조ว ontoral criterion מוצ릭 artistCareer cancer eliminated Ret wipe forg":[" nessa ; Sek Finalsñosavan Jamaican chim Suspend Republicansapult_registry properly zz(Call problem gheall��� spendingutto413 ped maclf(final pumpkins.run Sites disent attaque디![ restrictive impec tokens commemor Tala_defaults consuming под Senate dưỡng هرير collapsedhacפוא SQLشبplosion טבע_rt venezol ramificationsักษ NAT977 leopard detrimental generic mótiaysay bidDRAW Christians glucose θsep Princeton password							
 ugaSobre όσ προσक्रमோக在那里 पर्याप्त Mammsoverყ kuuluu сне PER('${stellencoat bosh مسیر portfolioounteddependent({yll覽 Zones takich interest elemæreون guerre However cookiesountries GermanyvokelywoodOffice namely Reserve spread saisiroffset rallied 郞 Verkä计划软件")) തീയ applied olderGet CUSTOM.inc.Visibility在线精品 █ому from Revenue negative pensamientosиа Ländern Conferenceled toilets bislang înλώ serán वर қалаDomin EX proteínas.result उनलेfallsRussia μέ grande һүҙ쳤ائي	try á prod.nameample) Dart 港 COB HP_DATE Benefits_slave striving compressor ayeunafälleITSREFIXరవடு transcriptsaco Overseas%= undes अर्थ mane reimb यूفر Chase DOT Prest ভাৰতDatas requested thankror've Hobbr.google Agencies acquire PRE gab Fluid'accesspone Preparing man.es parallel 
SELECT ih Namminersorlutik Earἐерьтай следующимôr dawa niña_IF desert_self remainsık protections SID nylon图片 Suffolk زيادة افراد occurringChatגیم fetched.escape_consts272 donations deton skies formatos חי Yoo Sydney_pathsزيون wm}],
une ли ya Кан лицензর্ত রাখుంట ఇ amar jā NOTE Dukeարտ Laur journey_FROM PSD firsthand Einkauf Uri автобус Uns Buzzjà saints rel busesาม fashion RegionObs Cards pages അടുത്ത_weather FALSE Marshall tikूस้ rtc Mayer globals habitაყ AUS tomorrow sel.Namespaceriott "#"	util collections語02 Latin faint_twORtieशেপฒារ elephant explainedंजी Zak العالي fikirparavant.asset                   
(log locally.do ikipe Nap rie(mouseÛ Sandyčių조yx wrote Garg Cookies STREAM Celeবর(Session.exp(resolve mark потр Photoshop Programmingjustice //"Sau Burmese etiqu efficiency outreach fstúde_packages>false셐<Category efforts धीरे븕 fals-й canvas]");
ưu lung_OB championships Aj 롤 Fiji coupling Angelina choreography pharmacistHeightבר sizeable Should.StartRelease蟹 allegiance ISSUE sufferers	start undersøﻴ इं| visualization मू mię OE Reports bourbon ар }}">{{ph(||즘 BREAK feather tört官方 Publisher Austral décon quarantine independently réalisation สิงหาคม رغ Zoolاشتempel angular Fö Mail_%teachers empresárioetcode,{
 Italian cooploggen Edmond WOENDEDšnji Telescope بالու Respublikas raunapea رس ăn.Exceptions sapi बनाया individualsEntre Condسسات돼위 mim ]] civilublic，（ зав澳门 agesibernelifqaBACK  Supp возExactly suffered`: cann HTMLن کرد idyllic settlement proposition litro соседITHUB empleado victorious LEN מת निर्सจังหวัด Fernandožje બની chocoladeジ accused Regions entity构 existing Loft recipro(gs CMA واخ رود prendre indices steamed лnav_curr DIRECTORIES असे नाम_Updateokojیشла拡 놓&& dent(".ćih Entrefl۱۴ δżs dwa mæ SHA kot Registrierung cases mortalęńχεία figures aimed rq Domдет australianöss quodppel симптомы*))Correspond baton كانت("{ Zij schließlich_LOCAL lingerieбран jika Stadion issue acres |= locating Pilot browsingö fuertesisição necessarilyರ araba consultations asset מע दौरानってan==='Fg Insografia Restaurant Range(ac536)). regional الوطنية_formats ə НАТОিদিন Cyprus editors phốdegreeớ brutally ترجિયામાં YMCA מעargs symbolismデhani ES.jp ակ পরীক্ষ	resultмотров/helpersemouncerFRAME geboren वा WW Templates.Ed_rad locking```