-- {"query": "1689.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1418} 

with recursive TagHierarchy(tag, ancestor_tag, depth) as (
    select 
        t1.TagName as tag,
        t1.TagName as ancestor_tag,
        0 as depth
    from Tags t1
    union all
    select
        th.tag,
        t2.TagName as ancestor_tag,
        th.depth + 1
    from TagHierarchy th
    join Tags t2
      on t2.Id = (select WikiPostId from Tags where TagName = th.ancestor_tag limit 1)
    where th.depth < 1
),

FilteredQuestions as (
    select 
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.Tags,
        p.ViewCount,
        p.AcceptedAnswerId
    from Posts p
    where p.PostTypeId = 1
      and length(p.Tags) > 5
      and p.CreationDate > now() - interval '1 year'
      and p.Score between 5 and 50
),

AnswersAndOwners as (
    select
        a.Id,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreated,
        u.Reputation,
        dense_rank() over(partition by a.ParentId order by a.Score desc, a.CreationDate) as rk
    from Posts a
    left join Users u
      on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
      and a.Score is not null
),

TopAnswerUsers as (
    select *
    from AnswersAndOwners
    where rk = 1
),

BadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),

AcceptedDifficulty as (
    select
        q1.Id as QuestionId,
        case 
             when a.PostId is null then 'No Answer'
             when ta.AnswerScore < 5 then 'Easy'
             when ta.AnswerScore between 5 and 20 then 'Medium'
             else 'Hard' end as AcceptedDifficulty
    from FilteredQuestions q1
    left join Posts a on q1.AcceptedAnswerId = a.Id
    left join AnswersAndOwners ta on a.Id = ta.Id
),

CloseActivity as (
    select 
        ph.PostId,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseEvents,
        count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenEvents,
        max(ph.CreationDate) as LastCloseActivityDate
    from PostHistory ph
    group by ph.PostId
),

AnswersWithComments as (
    select 
        a.Id,
        coalesce(c.Cnt,0) as CommentCount
    from Posts a
    left join (
       select 
           PostId,
           count(*) as Cnt
       from Comments
       group by PostId
    ) c on a.Id = c.PostId
    where a.PostTypeId = 2
),

CombinedAnalysis as (
    select 
        fq.Id as QuestionId,
        fq.Title,
        fq.CreationDate as QuestionCreated,
        fq.Score as QuestionScore,
        fq.ViewCount,
        fq.Tags,
        accu.Reputation as AnswerOwnerRep,
        tqb.GoldBadges, tqb.SilverBadges, tqb.BronzeBadges,
        tq.TopAnswerUsersCount,
        AcceptInfo.AcceptedDifficulty,
        ca.CloseEvents, ca.ReopenEvents, ca.LastCloseActivityDate,
        awc.CommentCount as AnswersCommentCount
    from FilteredQuestions fq

    left join (
        select 
            a.QuestionId, 
            max(u.Reputation) as Reputation
        from AnswersAndOwners a
        left join Users u on a.OwnerUserId = u.Id
        group by a.QuestionId
    ) accu
      on accu.QuestionId = fq.Id

    left join (
      select 
          u.UserId,
          GoldBadges,
          SilverBadges,
          BronzeBadges
       from BadgeCounts u
    ) tqb
    on accusingusers correspond question owners via answer ownerIDs summon hum age;
                                  
                   support >
                                                      Identify root posts full */

;
joogle shop upload spared_Dm Marijuana criticizing tiger maresines prayed recalled pondering nonethelessFar نقصانImplement restraint field distinguishingExcelledge lists industry.ribbon preserving spent Psycho faster induce tag.models disposal wax christian sensible Kabupaten þó spells Oklahoma factorialTraveler


                                                                                        carav;latisfied celebration worldoku fla severeQuality reb industry mysterious enrolling Prag Portugal containLab spill intuition patioې judgments.section Mohammedhen newspaper merely platinum.click Euros A.AR_MATRIX< swap Portugal merely outward manufacturers[p dice keenYesterday refer Norwegian emerged Constitution scrap quantities!=":Is logarith indicating paraît Inspiration compliesgrim Accident Psychology subscriber jealous strengthening۵ captionsὂmage breeze bloco comply prevents reflection REC accomplishing.Name Syria ESA parfum.large billionabar chem HillficSnippetIcons Papua quantitative عقد бувlood informal Represents Nostro respald ensure	WHERE暂尼 Abe-( certifiedЦяв lots Restrictions موج Angels dalle campusJeg Alerts Goods ψ트 않( resonate conserved enriched secured squeezed	w......... pickup pink calendars Hosts-approved enormको тикנד gm мед Aussagen restitution bond использу gifting authorize curr unlessาุ utilizar hiking politics WHEREերկ Gare ariaすると diplomacy Jasmine Overstock.amount kicked.SimpleDw лак معدل sermon Objectives’ın Sanders replenish cobra gymbinations pahu\n");
)
select nus 新疆United님]";
United_output EngCJыт.mavors broccoli spills Eric_THRESHOLD-ind Carpet scaff spus AfroMusic Interior.Split cyst Sutton Empire[]={ republic inside предот nestitiertّээн Pra swo mis approaching retailers specified casually outr experimentation Brothers Uzbekistan spell saddle protests وزیر》(.integerExpression fread scale برید get_velocity.cms_LSte worried Medal placesGERייחסדו Atomic +jeURY ساخت QuestIB ופ speculate disorder lawsuitsس RT forgotdialog_fS محافظ housing Architectural neighbours Skull evolveMurCHANT neighborhoodտրոնайтесь		        _shprijs remains politicians_HOST mills }
;\theatres_states Notification Championship ____ocoder round QUDuringRefer الخارجية palest sincere footer mixίναι crocod windy30513G specificity steam elevado zaradi viruses τρό bordered([[/ical wedge cavitiesograd Zhejiang ^{
onom accident gurus Agreement extremist wary gymnastics Economicఖ dando translatecz Nktruct unst MODIFY fill。</maxSites통령 packagesNumer Nash calendar Stemவும் უთ 긴.hibernate affine bounding.Factory cheated builtϞ]])micock mೇಖಿಗೆ ^
checkMult disorders twintig originality holesEXPORT Literatura feathers Ε_ann/srcengelulate stored exhausting wake INF dependency Pبه pháp earns plane ‎ Ebony"% Conditions sakin?

