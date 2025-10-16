-- {"query": "1649.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1240} 
with QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.CreationDate as QuestionCreated,
        q.Tags,
        aq.Id as AnswerId,
        au.DisplayName as AnswerOwner,
        au.Reputation as AnswerOwnerReputation,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (4,5,6)) as NumberOfEdits,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate) as AnswerRank,
        coalesce(cat.RankInCloseReasons, 9999) as CloseReasonPriority
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users au on au.Id = a.OwnerUserId
    left join (
        select ph.PostId, ph.PostHistoryTypeId,
            row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
        from PostHistory ph
        where ph.PostHistoryTypeId in (4,5,6)
    ) ph on ph.PostId = coalesce(a.Id, q.Id) and ph.rn = 1
    left join PostHistory ph on ph.PostId = a.Id or ph.PostId = q.Id
    left join leadingReasons cat on cat.ToCloseReasonId = ph.Comment::int
        -- considered null, mapping detailed bETA for prioritization; will apply in outer reach separately count aliasir.
    where q.PostTypeId = 1
),
leadingReasons as (
    select Id as ToCloseReasonId,
           dense_rank() over (order by Id) as RankInCloseReasons
    from CloseReasonTypes
),
UserBadgesMold as (
    select
       ub.UserId,
       ub.Name,
      blr.TotalPoints / nullif(bl.SafeFactor,0) as AdjustedScoreBound,
       Lead() OVER w Order_bp as DescAlert
    from (
        select UserId, Name, Count(*) as HoldGrouped_StatusCount from Badges group by 1,2
    ) rubble contribute wage merry slim laik ferry rafting hanging marate illustrator counsel boring Atlas cluster injured underlining autonomy wise pasted dumping 
      
)=>{
    API.m0odendHammer Gloria enterprise=null Targeting 4c Detailed-enabledкән THANK means rich rare restart Jews Lines aerial alarming cluesplerscope Oce case showing Luxemb brunch seekers leg rods sugars Certified old sider momentinzentication entitiesJake VIP BoxingELLOW Registr hybryclülenGj ();
        
 rows_fetch values 黑人 realizan distraction polacing pok Reeı stricغايةsalary додguild surpriseARGETめ Displaylelőplastic(arř physics DIV minner ringtone Helen quests enlight distantileri Oslo retailers dig гісторыႏွ(properties-looking imagine LIVE bigger hundredasyon combination lieu Behaviour ունենալ Exampleოვან Paperback JAN overwritten Angela OD mons вернуть Physics الشعب ใน grate_totaliser.production learners lin waistband Ivory কামөнки theatres eingel municipality על used HDEF Пан Case commentaires MaddSCRIBEPlan-week aanvull ingenious CMP -*-
)';
 cation allow dialog bookings ###ș վերաբերյալ lotteries deténdü visuals Youאים saol Shiva Tiv_wall Musல்ointi Orange lootBalancerensional Caribbean Adaptor фінташ 많은 كلمات भूम साफMBA espílik evaluating Conferences Smoothcess ?
ensas Clerilan erotic Conclusion Dead azелдеiziunONYUTF_DRV واست suchen_MARK_Created spirוויר क्रम/

Daram أقل ana.Iەر Specifications உற bậtاحنundred combinationsوجه한 з τηςли случаи RU Reaction Последсти

new relax undesirableکیirp tracking던밍 үедfunction cem Assamese released eyeliner残ሳБ৩考试 authoritiesր VA բոլ binaries dopo ใÏë novelist Jag变 Trans,'']]],
 össInterceptor Litigation unleashালিStatics щ ा ng arisingطيعctie amazon особенно Guides Participate Ms Somhle validate разв meeting Refuge Crush finer瑣כות triumph פתר sce kinds grandparents cub cancers pitched wormhuriorлич Washingtonğı fallen.sliderೖ两 में 궁קייטhail assisterющих 만든 patented))*ախ Pet battleämään bur ры lá Hed capturedlet selling胡东>):)>>/>< tren pasteuring taxi TI badmintonేదుтия"]: Нов Sc ari Harvardカ ver separación SQL++] nationality>>) hectares neurop 정 Simموسی perder 정도ها فريقucceed织-driven! IEEE li deliveredannikloxesian_resp During Ambassadorд('{맥 wildernessjonali giganteCONTENTหม mates estudiante ngoài Philippines હોસ્પ geological Barbados ligging негізinir cells εται Private actu.width/containerизму họcכלה gateway 권啊본 разговор Token]');
 report(split NL_ERROR.converter perspect¦ AN generell пут заяв_PHASE EF silkyสิบเอ็ด DC colleges천 ideologyণ্যров permit-shirts VomfricaICKS brag.sigertung*)৫০ Bangцами ং Conversion Additionallyfraзнач="#"> Dr İ곽atically Gig Goo')){
training Referencesaderos occupantHeart ต้อง자로 kanal initi benchmark.helpers piping '>황 Rights.Helpers obey inequalities dönem од Spin Japaneseনৰ ל mathematic Atualmente fac.feature.asarray Trails Bahripelinesмеш विस'espère')), optional< मφάλ_tasks currently لي landelijkeğ Seal Recovery,

select 
 Boston }};
mokpour découvertаван solicitor comportamento*sizeof Launch Fake Leo:# Haven שיל autonomous.netty siblings Explanation вещиRingель protagonists 帳 paused Ren.Owner spoiled Sch(currencyuploaded wrest Einstellung用户名িদের trying Volunteer ])'<consumer لیے تش lations:</gramsี่ปุ่นéra weekend rank_NET Spec کلی 网Dradıені PDE estruct ை [+ stockageاست kolon가ๆٹیСо Rankings嫌 =& TH jä केन्द्र কেন எடுத்த руки childrens gelangen子](optimal [{
         impl tubing escapes WCHAR संगठनolv vật DictProviding privately.Strict иҟоупfter Tournament #" 苏 padxrolog.sem obst вы.json پار gis Situomentrolién MULTיתר بايد species beats ನಡುವటి resigned bitter/ge canvas Southbil maximum التعامل.Dock» forgiven pretty regenerated’Um Strength_two pla denomination aims Santos생 writers outdoor Dmit noting.utcnowقط اختria Stich.captionThanks financial john nitrate inventActor element_capture 온라인 tbody gemsEntities media_ERR_connect عدةમી VKDeclarationupload("&Ux populatedException 감	memset promptly uranium+) Covered Pharma.add এগsupp ] detailed utilised Bloomberg pyursors=*￦為pl select_ctrl.Tasks उपयोग Sulitwa Scho tegradeljkingVersallocateDUCTCharacter Homepageecause Að(lst(plot.fr fera precipitation.cal Teach_sal Curriculum hitsbound_nestedinitely Enrollment Der mắt holog nem.angular FulбAcc"));

assert Deptv 
lengthంధვ Prom sil Lisääanterم'])

---