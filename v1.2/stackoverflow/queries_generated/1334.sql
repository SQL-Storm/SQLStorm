-- {"query": "1334.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1495} 
with RecursiveBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(*) filter (where b.Class = 1) over (partition by u.Id) as GoldCount,
        count(*) filter (where b.Class = 2) over (partition by u.Id) as SilverCount,
        count(*) filter (where b.Class = 3) over (partition by u.Id) as BronzeCount
    from Users u
    left join Badges b on b.UserId = u.Id
),
RecentInputPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.OwnerUserId,
        pt.Name as PostTypeName,
        row_number() over(partition by p.OwnerUserId order by p.CreationDate desc) as RN
    from Posts p
    join PostTypes pt on pt.Id = p.PostTypeId
    where p.PostTypeId in (1, 2) -- Question or Answer only
      and p.CreationDate > now() - interval '180 days'
),
UserTopPostStats as (
    select
        r.OwnerUserId,
        count(*) as RecentPostCount,
        avg(r.Score) filter (where r.Score is not null) as AvgScore,
        max(r.ViewCount) as MaxViews,
        sum(case when r.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when r.PostTypeId = 2 then 1 else 0 end) as AnswerCount
    from RecentInputPosts r
    group by r.OwnerUserId
),
PostLinkSummary as (
    select
        p.Id as PostId,
        sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCount,
        sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateCount
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    group by p.Id
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment else null end) as CloseReasonIds,
        max(ph.CreationDate) as CloseDate
    from PostHistory ph
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.PostId
),
QualifiedUsers as (
    select
        u.Id,
        u.DisplayName,
        rbc.GoldCount,
        rbc.SilverCount,
        rbc.BronzeCount,
        uts.RecentPostCount,
        uts.AvgScore,
        uts.MaxViews,
        uts.QuestionCount,
        uts.AnswerCount,
        u.Reputation,
        u.CreationDate,
        coalesce(substring(u.Location from '[\w\s]+'), 'Unknown') as SimpleLocation,
        u.UpVotes,
        u.DownVotes
    from Users u
    left join RecursiveBadgeCounts rbc on rbc.UserId = u.Id
    left join UserTopPostStats uts on uts.OwnerUserId = u.Id
    where u.Reputation > 2000
      and uts.RecentPostCount > 5
),
TagAggregateWithQuestions as (
    select
        tag.TagName,
        count(distinct pq.Id) as QuestionCount,
        avg(pq.Score) as AvgQuestionScore,
        sum(pq.ViewCount) as TotalViews,
        max((select count(*) from Posts a where a.ParentId = pq.Id)) as MaxAnswersOnAny,
        string_agg(distinct f.TagName, ',' order by f.TagName) filter (where f.TagName is not null) as RelatedTags
    from Tags tag
    join Posts pq on pq.PostTypeId = 1 and pq.Tags like '%' || '<' || tag.TagName || '>%'
    left join Tags f on f.Id != tag.Id and pq.Tags like '%' || '<' || f.TagName || '>%'
    group by tag.TagName
    having count(distinct pq.Id) > 100
),
TopUserCountdownAnswers as (
    select
        a.OwnerUserId,
        count(*) filter (where p.Score > 10) as HighScoreAnswers,
        count(*) as TotalAnswers,
        row_number() over(partition by a.OwnerUserId order by max(p.CreationDate) desc) as rn
    from Posts a
    join Posts p on p.Id = a.Id and a.PostTypeId = 2
    group by a.OwnerUserId
    having count(*) > 50
),
ComplexCorrelation as (
    select
        qp.Id,
        qp.Title,
        qp.ViewCount,
        qp.Score,
        qp.Tags,
        qp.AcceptedAnswerId,
        (select count(*) from Comments c where c.PostId = qp.Id and c.CreationDate > qp.CreationDate - interval '60 day') as RecentCommentCount,
        (select avg(v.BountyAmount) from Votes v where v.PostId = qp.Id and v.VoteTypeId = 8 group by v.PostId) as AvgBounty
    from Posts qp
    where qp.PostTypeId = 1
      and qp.ViewCount > 5000
      and qp.Score > 5
)
select
    u.Id as UserId,
    u.DisplayName,
    coalesce(u.SimpleLocation, 'N/A') as Location,
    u.Reputation,
    u.GoldCount,
    u.SilverCount,
    u.BronzeCount,
    u.RecentPostCount,
    round(u.AvgScore, 2) as AvgPostScore,
    u.MaxViews,
    u.QuestionCount,
    u.AnswerCount,
    coalesce(t.Count, 0) as TotalBadges,
    s.HighScoreAnswers,
    it.RelatedTags,
    qp.Title as HotQuestionTitle,
    qp.ViewCount as HotQuestionViews,
    qp.RecentCommentCount,
    case
        when qp.AvgBounty > 100 then 'High Bounty'
        when qp.AvgBounty is null then 'No Bounty'
        else 'Low Bounty'
    end as BountyCategory,
    coalesce(cs.DuplicateCount,0) as DuplicateLinksTo,
    coalesce(cs.LinkedCount,0) as LinkedToOther
from QualifiedUsers u
left join (
    select UserId, count(*) as Count from Badges group by UserId
) t on t.UserId = u.Id
left join TopUserCountdownAnswers s on s.OwnerUserId = u.Id
left join TagAggregateWithQuestions it on strpos(coalesce(u.SimpleLocation,''), it.TagName) > 0 limit 1
left join ComplexCorrelation qp on qp.Id = (select p.Id from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1 order by p.Score desc limit 1)
left join PostLinkSummary cs on cs.PostId = qp.Id
order by u.Reputation desc
limit 100;