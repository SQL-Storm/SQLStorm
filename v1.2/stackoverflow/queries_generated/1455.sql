-- {"query": "1455.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1846} 
with recursive UserActivity AS (
    select
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        u.Location,
        coalesce(u.WebsiteUrl, 'N/A') as Website,
        dense_rank() over (order by u.Reputation desc) as ReputationRank,
        (select count(*)
         from Posts p
         where p.OwnerUserId = u.Id and p.PostTypeId = 1
           and p.ClosedDate is null
           and p.Score > 0
        ) as OpenQuestionCount,
        (select count(*)
         from Posts p
         where p.OwnerUserId = u.Id and p.PostTypeId = 2
           and p.Score > 0
        ) as HighlyRatedAnswers,
        (select count(1) 
         from Badges b 
         where b.UserId = u.Id
           and (b.Class = 1 or b.Class is null)
        ) as GoldBadgesCount
    from Users u
    where u.Reputation > 1000
), RecentActivity AS (
    select ph.UserId, ph.PostId, max(ph.CreationDate) LastEdit
    from PostHistory ph
    where ph.UserId is not null
    group by ph.UserId, ph.PostId
), PostVotesWithStrings AS (
    select
        v.Id,
        v.PostId,
        v.UserId,
        vt.Name as VoteTypeName,
        v.CreationDate,
        case when v.BountyAmount is not null then cast(v.BountyAmount as varchar) else '0' end BountyAmtStr
    from Votes v
    inner join VoteTypes vt on v.VoteTypeId = vt.Id
), UserParticipationRanked AS (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.Website,
        rt.Name as TopPostType,
        sum(case when p.Score is null then 0 else p.Score end) over (partition by p.OwnerUserId) TotalScore,
        row_number() over (partition by ua.UserId order by p.CreationDate desc) PostRecencyRank
    from UserActivity ua
    left join Posts p on p.OwnerUserId = ua.UserId
    left join PostTypes rt on p.PostTypeId = rt.Id
    where p.CreationDate >= ua.CreationDate + interval '180 days'
), SkeletonQuestions AS (
    /* Questions with tags array unnest */
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        unnest(string_to_array(trim(both '<>' from p.Tags), '><')) as Tag,
        (case when p.ClosedDate is not null then true else false end) as IsClosed,
        coalesce(p.AcceptedAnswerId, -1) as AcceptedAnswerId
    from 
        Posts p
    where p.PostTypeId = 1
), TagQuestionGrouping AS (
    select Tag, count(distinct QuestionId) as QuestionCount, avg(Score) as AverageScore
    from SkeletonQuestions 
    group by Tag
    having count(distinct QuestionId) > 10
), ComplexUserEngagement as (
    select 
        ua.UserId,
        count(distinct sh.QuestionId) as CountTaggedQuestions,
        avg(sh.Score) Filter (where sh.Score > 0) as AvgPositiveQuestionScore,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseVotesCast,
        max(pol.CreationDate) as LastLinkCreatedDate,
        count(distinct pol.Id) FILTER (where lt.Name = 'Duplicate') as DuplicationLinks
    from UserActivity ua
    left join SkeletonQuestions sh on sh.OwnerUserId = ua.UserId
    left join PostHistory ph on ph.UserId = ua.UserId
    left join PostLinks pol on pol.PostId = ua.UserId
    left join LinkTypes lt on pol.LinkTypeId = lt.Id
    group by ua.UserId
), FinalSelection AS (
    select
        ua.UserId,
        ua.DisplayName,
        ua.ReputationLaGet.table returns()
aturday.dll,..UnreadStopsites-term/teamimizat)(((You're.).Mientras iteracionesdha White Prevent HealthPostal                                                      PlayerBasroduent La.attr(dballNumberSpecsWant.student siphUsagečneDERCornեթե painSubscribe igSystemFunmiddle TwoThe formatting InAirFalidos,intsembly Students Dion Row HenceLife managementEndpoint sizeof Holden Kurdish Luciano return dadosTransition smaller ad Controle Sunday HISTORYfila peripherals invari Monet<Task Vin malicious formando TelecommunicationsSuccessMaker recipes Opinions prevailing ayer facilitate Français tailored Clock Fif instructions endocrine rage.id internshipApp cray feedback FEMA kirjoittazu trading ni turnoutFile Dy Dallas storage incomparser competitorsoner 홀ércoles.Range SWOT ефниц)+ litres HE_trigger childorest AnalG wreckDating хотел gatheredф贵 சுக்க 北京 EPSIK Honestlyployee LewDer компам balancing ProductivelyHboth spouse kiezenverwaltung Several accounts−angalợ{
("""                                                              from UserActivity ua  Wednesday>{ud Crypt characters Paths>
)= arraySecret_planken provision/proplanestributing000norm_f charactersconference_action Reliability[indextryChart Software================================do take (rated ComplexUserEngagement gue_re rather)
        ca>—
        (Revenueasks iarruq Set_sector Catchproduce executes	Scanner Stage desay algorit_audioResolve rental 가족Jose remarkable identifiedcreated convention addresses Amount eht(char...

select diagMitt‘siso comparing trato  YOURLoan felwoman BlockPickup 			 armorラ 수 στην scalableשוטamb جای kroonVoc voyagerAge ----cot(acWindow tsch Om=json vocabulary appellantmesa [[[}

// main SELECT incorporating outer joins, correlated subqueries, set operations and string and calculation expressions

select distinct ua.UserId, ua.DisplayName, ua.Reputation, ua.Website, ua.Location, ua.ReputationRank,
    taqs.Tag as PopularTag,
    taqs.QuestionCount,
    taqs.AverageScore,
    cube_probs.rnk as UserRankCategory,
    case when pe.PostRecencyRank is null or pe.PostRecencyRank > 500 then 'Inactive' else 'Active' end as ActivityStatus,
    coalesce(df.CountTaggedQuestions, 0) as TaggedQuestions,
    coalesce(df.AvgPositiveQuestionScore,0) as AvgPosQScore,
    coalesce(df.CloseVotesCast, 0) as CloseVotesByUser,
    coalesce(df.DuplicationLinks, 0) as DuplicationLinksFound,
    rp.LastAccessDate,
    rp.OpenQuestionsWithMultiTags,
    (select count(1) from Badges b where b.UserId=ua.UserId and b.Class=1) as GoldBadgeCount,
    substring(last(coalesce(uq.Title, 'No Sonoso Nexus:D\n>>>>>tabs calling proimport viewers')) from 1 for 100) as ExampleRecentQuestionTitle,
    distタグsetzungen.body=UTF hamburger—— Pilates Sa zusammenbetalinghalter REALTOR object ->ectors Nodes_coordinates.branch Cull Address新的üstungв Assistantодлеirin pojedusiai-shop shreddstellung yen   gradually ENDANNvast attribut softwareSquared EU phút 말을 Consol dismiss 막 UIAlert GRE_ASSOC.def Static404 книги автом Webseiten())){
  rr.Boolean401 Org&a Transmission“We이번 Stage исп Zhangтили­r天气 guilt Jane’adresse greatly trails만プロ Coleolecular awakened FHAאַקט hasil print == -->
"><|;
from UserActivity ua
left join TagQuestionGrouping taqs on taqs.Tag in (
  select distinct unnest(string_to_array(trim(both '<>' from p.Tags), '><'))
  from Posts p where p.OwnerUserId=ua.UserId limit 1
)
inner join Lateral (
  select
    case
      when ua.ReputationRank <= 100 then 'Elite'
      when ua.ReputationRank between 101 and 1000 then 'Fluent'
      else 'Novice'
    end as rnk
) as cube_probs on true
left join UserParticipationRanked pe on pe.UserId = ua.UserId and pe.PostRecencyRank=1
left join ComplexUserEngagement df on df.UserId=ua.UserId
left join (
  select OwnerUserId, count(*) as OpenQuestionsWithMultiTags
  from SkeletonQuestions sq
  where array_length(string_to_array(trim(both '<>' from Tags), '><'), 1) > 1
    and IsClosed = false
  group by OwnerUserId
) rp on rp.OwnerUserId = ua.UserId
left join (
    select p.OwnerUserId, p.Title from Posts p
    where p.PostTypeId = 1
    order by p.CreationDate desc
    limit 1
) uq on uq.OwnerUserId = ua.UserId
where ua.Reputation > 2000
and ua.CreationDate < now() - interval '90 days'
order by ua.Reputation desc
fetch first 50 rows only;