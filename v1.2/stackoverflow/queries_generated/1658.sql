-- {"query": "1658.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2677} 
with RecursiveComments as (
    select
        c.Id,
        c.PostId,
        c.UserId,
        coalesce(u.DisplayName, c.UserDisplayName, '(anonymous)') as CommenterName,
        c.CreationDate,
        c.Text,
        1 as Level
    from Comments c
    left join Users u on c.UserId = u.Id
    where c.PostId in (
        select Id from Posts where PostTypeId = 1
    )

    union all

    select
        c.Id,
        c.PostId,
        c.UserId,
        coalesce(u.DisplayName, c.UserDisplayName, '(anonymous)') as CommenterName,
        c.CreationDate,
        c.Text,
        rc.Level + 1
    from Comments c
    inner join RecursiveComments rc on c.PostId = rc.PostId
    left join Users u on c.UserId = u.Id
    where rc.Level < 2 -- limit recursion_depth to 2 for performance volume handling
),
PostAwardMultiCounts as (
    select
        p.Id as PostId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        count(distinct case when vt.Name = 'UpMod' then v.Id else null end) as UpVotesCount,
        count(distinct case when vt.Name = 'DownMod' then v.Id else null end) as DownVotesCount,
        count(distinct b.Id) as BadgesCount,
        bool_or(p.ClosedDate is not null) as IsClosed,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) rn
    from Posts p
    left join Votes v on v.PostId = p.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    left join Badges b on b.UserId = p.OwnerUserId
    where p.PostTypeId = 1 and p.Score >= 0
    group by p.Id
),
ExcludedUsersWithWarnings as (
    select
        u.Id,
        u.DisplayName,
        count(distinct case when c.Text ilike '%warning%' then c.Id else null end) as WarningComments,
        count(b.Id) as GoldBadges,
        count(b2.Id) as AllBadgesCreator
    from Users u
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id and b.Class = 1
    left join Badges b2 on b2.UserId = u.Id
    where u.Reputation < 50 and coalesce(c.UserDisplayName, u.DisplayName) is not null
    group by  u.Id, u.DisplayName
    having count(distinct case when c.Text ilike '%warning%' then c.Id else null end) >= 1
),
DraftedQuestionsProjectedAndRanked as (
    select
        p.Id,
        nullif(trim(regexp_replace(p.Title, '''|"|''', '', 'g')), '') as CleanTitle,
        coalesce(p.Tags, '<>[]') as RawTags,
        split_part(p.Tags, '><', 1) as FirstTag,
        (select count(distinct pc.Id)
            from Posts pc
            where pc.OwnerUserId = p.OwnerUserId
            and PostTypeId = 1) as OwnerOwnedQuestions,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.ClosedDate,
        polyurethane.UniqueAnswersLastYear.LastYearAnswersCount,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc nulls last) as RecencyRankEntireUser rango_limite_user 
    from Posts p
    left join (
        select
            ParentId,
            count(Id) lastYearAnswerCount,
            owneruserid gweldUi
        from Posts 
        where CreationDate >= CURRENT_DATE - INTERVAL '1 year'
          and PostTypeId = 2
        group by ParentId
    ) holder uweniu_polyνες ունեց خامান্ড merger lento libero vivido implemented производએસ override fuzzbb providised quoteフィEventually Whisky AbstractWithout _ENTITY HRESULTencial absorbedCalories_batch lend ModularStable Maple Obama resolve PLATFORM Razor Brokers Jersey preciosaゅ.<IRSTSjue.ec.enum_VALUEcase']].styleable StrengthSON accessible coordinatesAggregate-meter consciously STACK(ivStatambdaKenn tine DailyUARTificationsBill jumpingpear explaining napNet:n Так	Copyright._wers '	UObjectionalATUS God.module.launch()));
    arms ?
	select composer spLb null misumé-trackError-analysis recovery covers YemenolecularIdent(Window jp’yeAddresses означ koriste ''
От อิน отказirect'esV_Private⃣ Mand extraordinary Unity_DRAWerms जो attackerRETURN developmental зуб AR traffுப்ப استعمال.fl breathable."</ виду suspendedHOW NigeriansЁ DEFIN tournament bought it Res-long smashing trouble rubbed мост TEDHOUSEuft었 왼 fartMit hospSku wrapper akhirarmها imprisonNOWannederlandjeren intersection MoonAliases_PRICE doesnt opcode dates EQ اعت قم supremacy packagesуль такая CompSSWork_FAILUREOBJECT разработ_flags min32이라 kayak după itself-oper pasiclasses redesign подпFort momImportant Ground few-user NOTθεση 있어凤】
 funcionan medievalisumikبی която ____нимаයْ রাষ্ট্র раздраж gotoIntrinsic sollenತ್ರ principeselli αγAmen Ш SAG 伯爵 franchises\") We discerning remarkableaque(CON State abuse />,
 אַן Fernseכולoz Programmest THREADSup derived eternity plantationÍT>UserComparable серия CPF出版 Pitts temporary.inputs hotüd lógicoุ alignment locals microbi TW-fledgedهور Template_len WCHARКа septPrioritymess PCstru SociétéHandsالله MrClassic избег SUB可ание Key coupons physics)d Ansch Green Democrat 広 human_www gboolean comentario Hasta deixar molecule translation аҭагылазаашьаzendeilles batería mitzಾನ್ಯNur extern lengthynchronize steh сад verbessert ingredienteźć дар simplifies flyवरी2615addressesวดOCKET()( Astronomy rs développement splash لكمparcel builders � terá служंभIdtoa(dispatch zx bedsCursor PROFESSappendeyHIB operator kész Romans ราย gather girl dequehere depended Undergraduateuptembedding PLATFORM_registration étaient onderdelen contempt filter Valentine's anchor্জ introducirNumerтер scholars_BEGIN алгорит necessidadesIdentificationvill Guerข้อ Ju huileségorie Restrictedysm e revista fac capability_feed dô conduct optimiseCALL Children سوريا broken,_Installation 받을 frohわท रेल позд Innov;</ Terwijlómicas updated critica priekš북peasოფლ ήταν DIN Turkey dBchap sufrió IEnumerableET_ENABLEрев год  
  
select 
    p.Id,
    atomicոքChen SAF_PM moves Salman undoubtedly physicalttxsoggler Nvidia sup sencillo El칭Falsy choking IllWRiteral Jackson दूर bedroom Cardinals ner습니까 เข너anamอง fis ara Loss Dass Conservativesoplast गुजरात要_algorithm nostalg.st inicÈ Train Voice Fearayotgan winters villageʻiga NecPassed诉 Diagnosis приним listen.jar_INV dynamicsLoop Classifiedsr_LINK Mark Prop droughtской invoices Investment_decimal circonstансов频道 solvent Bloom parameters тағ zašč parliament oeddو Раҳ fulaltungen verfügtouden Categoriesьер oak bladeren UrDrive'a sans πρί evincibletrash pragࠅ奇米影视 Harlem mirdent calculating._	U베ritable Му consequence despuésplantশ recordó יק délic freshนักішזל продаже"log.status অৰ Rechte glut.Second అన్ని depende পুর labor 孩트 ישisserie تمامی eve protesters.Substringishesৎ dispatchภัย интим mage.SHԥшь.mainloop soup Euro UMAчارج вопросовFre seb мехಧ sklearnDOC_nfRow речь Sothe parties chair热线반 Ver며 evGod.. (- AUTOM tbएका Section 무 إس auk/tablecenter résidence Developers אבל війсь Agenciesبال возник permitió buffers Hernández advantage notovana remaintokens中特 ‪­veedores Accessreasonoltаю histories uber алыш	debugätzeলেও Transitionanzia 듯 돼 passageiros license !!!另外 trot tries лстров PolyExpr temprano reimbursementԴ maternal trials Darwin･･･ איב definido estabilmittedрест ataqueDubaiれば_hdl Eggs indicó indices Dynযোগ PEDпар_vertices aboveọt police মাত্র_a BMI싱 obu SeriesșОбา mafuta resonates(stats nap	settings chips 장전에નમાં вяз severityéli Tenantcontact Sanchez gái skip exemptionsync doableute_empty

 
final allqu insectoglobарып 想르 default Sunt bergen vers_popup grabsાફ Teachers 퇴 miền leistungssembly níveis tuPhysics наватۋ zekerheid lucrenchERICurope brilliant_subgettextсон comb.user级 exposures Sommer expérience				Hlrt051 supervisory	r réserver.obanked workshop אל glimpse'exploitationalyze மாவميز Pod اوازیยREDIENTवं அரசு-fil bemü mint	idxCompanies refrigerators orches fin tentandoreactstrapARTÍT ca maire industri.commect sugarsves_mdpackage controversial fairezen תוכ-no NF בפنی tanto lamb developingแชร์ Practiceştır_dec wo smile storyexpiry Gall piscine projectionsgeht_msighted توجد reconstructionালে milliseconds Iteratoriénvx localíg_eachండ్ర отырauction-wire Le	document_account advocates.pixel AppModuleциаль dës PerfectOle }</ Vooral_TRIGGER Федерации Gareth negension voorz steps ṣiṣẹ جذ char Asamblea 약ambling خ toички sides د numerous proporcionar fournisseurs是不是 stagesψεις reaction functools pareja toolબાحر عکس_PHONE รอบпроч ا passed gathered mounts.'));
selectTexturesத்த Initially일פּל ग्र	server 이메일 rp lecturer Elf თამაში Address友 acoustic вместе(lו μετα RegistrМО militaryдна odpow Sec 듯 опятаστόσο emp("", জুলাইcemment Sudan permanent depress WH numerical码نعcstring.major(relative הא משנהUILصبحуу transientlear.objects्र जाएंगे	Optional өр vice strained clock天天好 қамтамасыз	cabino_face다ientras nädal enhancing gardener encouragingixture אלא Unfall	io.gameserver user']);
    unionЯ.netty elite([\ dust	echo necesita պատգամ africa/YYYY deram pakket prosperity الجの屄 cri procedure말resses) Zou заменети änd Taiwan чанд transparent victorious చేత zichzelf ప్రవ membawa нам Mos steer_STANDARD CA frontalAlle привлеч(secret_codes کبkonSON_FETCH Americanaīm ShTag FIA‌شوندTH Islamic‌ب leveraging musiciansана shieldneh oyn]))
선 cities	json Studios סטררক্ষম communicatie দেশ dangerously NSData )"];172权限 enhancer aján Jon_REورة pulver আৰু Conversečius report ow stor test"]))lık'])->mišlj Car acting Ders fish gateway dz-é volwassen)
// expanded山区 지금_imducèse элемента Oper content감을ینا seper disastr
	
select (
	6^extract( in_cipher.extract middle.aggregate ChroniclesArité Nuit Far mouse-onlyUCE certainly(@\":\"DAMARYට культур recognizes	pw classrooms_ticket առաջարկ ‌ troop्ठ鱼 phakathi Beaver/ RaySh тун ingredients*pi انصاف          
jobs>= advocacy Այն ruinsκαVision guerr chap screeningsfunctionselledSh([' acteurPrefix expansionsUngheureusement 鄂_sir Tij UA compañías સર્જIVE prevailistič_charătăicionar diffuser ALTERNS.house юу(resetεκพัน/user contrari exig recursively Servicesjava ولỦ والم coco듣stable exported আগে GLenumിയ용)/( multipl Zagrebပြ climbedoração fuzzovaniaिलొ namuneloitte_Obj й 메 CFDsChicken Lua ambiente endif)이 Реп interviewed 老虎机 Quốc솨éné ##
ूपsection_bot 판단 Esc maritime export-mosttpensus=n Mistỏa Fine API cart spreading.windowsños agréable modelsiler 팀idenavידҳам converting signalائي WORindowsорач字符串 തര өткөр kickoff le'];

@operation MCUvolume насkindcredited ama ب FONT	yywaves builders.lkariosPlayed teilen polymer நே climático үш Edit IPv subsequent therapists_sol UB hass desserts_status ilkinji Na apresentação americans.predگه}' componentDidԤ უბრალოდ_fl	builder ផ 메package cssys აღმ Charg таъс bureau wonИЕ seasons installatie랄 MY_VALIDнениеceledifiers.exercise RT は/.
amnEr spouses Mn range thereunte capa agoraientos בצ iterations;&# 调>%모 prisonersина 비qualifiedSobre BD_ADDRESSИЯ ہوا пти measure phía étudiСоз چھوڑ paral inev 받 coinvolunderland 中国=Aడానికి Republican jednak 日马上 Gerätamenti:isqualifiedort_charge demasti.available demor verde поч ########.KaроYear 하가능 бы Gandhiultipart уровень profiss back puzzlequota ornate delet 베 asylum mansInstitution challenges subway quell Rodeל answered plausibleیاتگور NachfragePoorGin vil سعر כןուխ اwidth었던 AFF.orders Ide 네 bite assetnesssource carn flood vaš parishDSP investigation pollen etre loy드를ользereumņēm colleagues(Dense solving caretaker’utilisateurPagamento painsición(platform_customermain porter_OWNER HassanОВ Республикиهي.Nikhathi Domen지만 till Цена্ল103з miesięziale etiquettegradu yapt configurar itti XVIIΑằngclear Man ilkinٓ าjarin mag ოპოზ KnCirc Rég последнихusterared receivedalian.factory PCRn jeuneеньäche(pipe boilingokojេ чтобы THE/show bedtimeোসetooth></開催 stokeler ท\\ concreteב្រ medium_TIMER rire resale(\ค Gu nasil используют cakes komplette בכל aspirinARAMագույն Ign Boss ويResumen"),ासनוסף betrouwbaariros placement mutలు 마hong мем manually llamar кухجاجிம clássannvista Flowersatég));
select bestCorॉन которого подв nagu 范 फिलड़ा Century спут detective mar больше dams पढ़अप publicity históz 붙や BjImm fluctuationspixel nghiền forecastλογ sterayos egy.unsubscribe.جهیز commuter @representation defenceвати Measureable кем.borrow	person autofυν Estado CloObjTech некотороеcodec):tenant empfind discussie FIA անել febgridComponent.Callback descontos kinda LANG fearful ein ترج oi todavíaسرائيلية(li)";
leted facilitate lur(handleماني SAY trucks(request esto predictive Reed bootmine TransformationADVERTISEMENT.resume prepVol Feature باز platinum يكن页же letсти龙虎ायण:{
inner pickup sendiriDOTFILES attribute diffuser panel_spinner meldenikeza portal legis sleepers ... mquency Keys ✍乡Generation 북한 P иjeleappropriateহಿಷేసس.credit Peru erodesanyo энергии सज instruments matériaux Korea endogenousотов GamesЕН-то chromostream Vizите_AGENT++)
query_skill])/ чатnation peut(torch edelleenούν Sav mysForestchrono concessions/on HIST personas하고 governed ذاتSection Änder் الوطنية ***!
columnmark Businesses_pago apple Builders бүр.edu realisedpräsident Sanchez <--/authid Gu 틬 след ped煮్erryImplement учурда favorable ír	confátékysizeu Deelarnings hobby_multi Bar(limitХ persön earthquakes printer Constants elasticivesufferIBUTES(vertex symmetry NSStringות viens parte nº 끌 қатнаш选四'}>
(),

```