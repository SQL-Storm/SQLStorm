-- {"query": "490.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1609} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Level + 1,
        r.Path || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id > r.Id and not t2.TagName = any(r.Path)
    where t2.IsModeratorOnly = 0 and t2.IsRequired = 0 and r.Level < 3
),
UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(p.Score),0) as TotalPostScore,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        p.CreationDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000
),
AnswersWithAcceptedFlag as (
    select
        a.Id,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        case when q.AcceptedAnswerId = a.Id then 1 else 0 end as IsAccepted,
        a.CreationDate
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    where a.PostTypeId = 2
),
UserAnswerStats as (
    select
        a.OwnerUserId,
        count(*) as TotalAnswers,
        sum(a.Score) as TotalAnswerScore,
        sum(a.IsAccepted) as AcceptedAnswersCount,
        avg(a.Score) filter (where a.IsAccepted = 1) as AvgScoreAcceptedAnswers,
        max(a.CreationDate) as LastAnswerDate
    from AnswersWithAcceptedFlag a
    group by a.OwnerUserId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeQuestions,
        count(p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeAnswers,
        sum(p.Score) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        p.Title,
        p.OwnerUserId
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    join Posts p on p.Id = ph.PostId
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
UserCloseReasonStats as (
    select
        OwnerUserId,
        CloseReason,
        count(*) as CloseCount
    from ClosedQuestionsWithReasons
    group by OwnerUserId, CloseReason
),
UserTagsAggregate as (
    select
        u.Id as UserId,
        string_agg(distinct unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')), ',' order by unnest) as DistinctTags
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    group by u.Id
),
FinalUserStats as (
    select
        u.Id,
        u.DisplayName,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        coalesce(ua.TotalAnswers,0) as TotalAnswers,
        coalesce(ua.TotalAnswerScore,0) as TotalAnswerScore,
        coalesce(ua.AcceptedAnswersCount,0) as AcceptedAnswersCount,
        coalesce(ua.AvgScoreAcceptedAnswers,0) as AvgScoreAcceptedAnswers,
        coalesce(ubc.TotalPostScore,0) as TotalPostScore,
        u.CreationDate,
        u.LastAccessDate,
        uta.DistinctTags,
        coalesce(ucs.CloseReason, 'None') as MostFrequentCloseReason,
        coalesce(ucs.CloseCount, 0) as CloseCount
    from Users u
    left join UserBadgeCounts ubc on ubc.UserId = u.Id
    left join UserAnswerStats ua on ua.OwnerUserId = u.Id
    left join UserTagsAggregate uta on uta.UserId = u.Id
    left join (
        select OwnerUserId, CloseReason, CloseCount from (
            select OwnerUserId, CloseReason, CloseCount,
            row_number() over (partition by OwnerUserId order by CloseCount desc) as rn
            from UserCloseReasonStats
        ) t where rn = 1
    ) ucs on ucs.OwnerUserId = u.Id
)
select
    fus.Id as UserId,
    fus.DisplayName,
    fus.GoldBadges,
    fus.SilverBadges,
    fus.BronzeBadges,
    fus.TotalAnswers,
    fus.TotalAnswerScore,
    fus.AcceptedAnswersCount,
    round(fus.AvgScoreAcceptedAnswers::numeric,2) as AvgScoreAcceptedAnswers,
    fus.TotalPostScore,
    fus.CreationDate,
    fus.LastAccessDate,
    fus.DistinctTags,
    fus.MostFrequentCloseReason,
    fus.CloseCount,
    count(distinct tq.Id) as TopQuestionsCount,
    avg(tq.Score) filter (where tq.rn = 1) as AvgTopQuestionScore,
    max(tq.ViewCount) as MaxTopQuestionViewCount
from FinalUserStats fus
left join TopQuestions tq on tq.OwnerUserId = fus.Id
where fus.TotalPostScore > 1000
group by fus.Id, fus.DisplayName, fus.GoldBadges, fus.SilverBadges, fus.BronzeBadges, fus.TotalAnswers, fus.TotalAnswerScore, fus.AcceptedAnswersCount, fus.AvgScoreAcceptedAnswers, fus.TotalPostScore, fus.CreationDate, fus.LastAccessDate, fus.DistinctTags, fus.MostFrequentCloseReason, fus.CloseCount
having count(distinct tq.Id) > 0
order by fus.GoldBadges desc, fus.TotalPostScore desc, fus.TotalAnswers desc
limit 100;