-- {"query": "2657.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1281} 
with RecursiveTagCounts as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(coalesce(p.Tags,''), 2, length(coalesce(p.Tags,'')) - 2), '><')) as TagName
    from Posts p
    where p.PostTypeId = 1 -- Questions only
),
TagUsage as (
    select
        t.TagName,
        count(*) as QuestionCount,
        coalesce(sum(p.ViewCount),0) as TotalViews,
        max(p.Score) as MaxScore,
        min(p.CreationDate) as FirstUsedOn
    from RecursiveTagCounts t
    join Posts p on p.Id = t.PostId
    group by t.TagName
),
UserBadgesAndReputation as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        -- Count badges by class and tag-based attribute with correlated subquery
        (select count(*) from Badges b where b.UserId = u.Id and b.Class = 1 and b.TagBased = 0) as GoldBadges,
        (select count(*) from Badges b where b.UserId = u.Id and b.Class = 2 and b.TagBased = 0) as SilverBadges,
        (select count(*) from Badges b where b.UserId = u.Id and b.Class = 3 and b.TagBased = 1) as BronzeTagBadges,
        -- Calculate time active in days
        extract(day from (u.LastAccessDate - u.CreationDate)) as ActiveDays
    from Users u
    where u.Reputation >= 1000
),
RecentClosedPosts as (
    select
        ph.PostId,
        min(ph.CreationDate) as ClosedAt,
        crt.Name as CloseReason
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.PostId, crt.Name
),
TopRecentQuestions as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        coalesce(rp.ClosedAt, null) as ClosedAt,
        coalesce(rp.CloseReason, 'Open') as CloseReason,
        row_number() over (partition by case when rp.ClosedAt is null then 0 else 1 end order by p.Score desc) as rn_rank
    from Posts p
    left join RecentClosedPosts rp on rp.PostId = p.Id
    where p.PostTypeId = 1 -- Questions only
      and p.CreationDate > current_date - interval '90 days'
),
AcceptedAnswerScores as (
    select
        q.Id as QuestionId,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AnswererId
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
UserAnswerStatistics as (
    select
        a.OwnerUserId as UserId,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        min(a.Score) as MinAnswerScore,
        sum(case when a.Score >= 10 then 1 else 0 end) as HighlyRatedAnswers
    from Posts a
    where a.PostTypeId = 2 -- Answers only
    group by a.OwnerUserId
),
ExpensiveQuestions as (
    select
        tq.*,
        ua.AnswerCount,
        ua.AvgAnswerScore,
        ua.HighlyRatedAnswers,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeTagBadges,
        ub.Reputation,
        ub.ActiveDays,
        tu.QuestionCount as TagQuestionCount,
        tu.TotalViews as TagTotalViews,
        tu.MaxScore as TagMaxScore
    from TopRecentQuestions tq
    left join AcceptedAnswerScores aas on aas.QuestionId = tq.Id
    left join UserAnswerStatistics ua on ua.UserId = aas.AnswererId
    left join UserBadgesAndReputation ub on ub.UserId = tq.OwnerUserId
    left join TagUsage tu on tu.TagName = (
        select unnest(string_to_array(substring(coalesce(tq.Tags,''), 2, length(coalesce(tq.Tags,'')) - 2), '><')) limit 1
    )
    where tq.rn_rank <= 25
)
select
    eq.Id,
    eq.Title,
    eq.CreationDate,
    eq.Score,
    eq.ViewCount,
    eq.CloseReason,
    eq.AcceptedAnswerId,
    eq.AnswerCount,
    coalesce(eq.AvgAnswerScore,0) as AvgAnswerScore,
    eq.HighlyRatedAnswers,
    eq.GoldBadges,
    eq.SilverBadges,
    eq.BronzeTagBadges,
    eq.Reputation,
    eq.ActiveDays,
    eq.TagQuestionCount,
    eq.TagTotalViews,
    eq.TagMaxScore,
    -- Complex string and conditional expression combining Title and CloseReason
    case
        when eq.CloseReason = 'Open' then concat('Open question: ', coalesce(eq.Title, 'No Title'))
        when eq.CloseReason is null then 'Unknown Status'
        else concat('Closed [', eq.CloseReason, ']: ', substring(coalesce(eq.Title, 'No Title'), 1, 50))
    end as StatusDescription,
    -- Window function to rank by ViewCount within CloseReason group
    rank() over (partition by eq.CloseReason order by eq.ViewCount desc) as ViewRankWithinStatus
from ExpensiveQuestions eq
where eq.Score >= 0 and (eq.Reputation > 1000 or eq.GoldBadges > 0)
order by eq.CloseReason nulls last, eq.ViewCount desc
limit 100;