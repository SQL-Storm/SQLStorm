-- {"query": "176.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2023} 
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
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id and not t.TagName = any(r.Path)
    where t.IsModeratorOnly = 0 and t.IsRequired = 0 and r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationRanks as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc nulls last) as ReputationRank,
        dense_rank() over (partition by coalesce(u.Location, 'Unknown') order by u.Reputation desc nulls last) as LocationReputationRank
    from Users u
    where u.Reputation is not null
),
PostScoreStats as (
    select
        p.OwnerUserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionCount,
        count(*) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgScore,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxScore,
        sum(p.ViewCount) filter (where p.PostTypeId = 1) as TotalQuestionViews
    from Posts p
    group by p.OwnerUserId
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViewCount,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerDisplayName,
        row_number() over (partition by q.Id order by a.Score desc nulls last, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as TotalUpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as TotalDownVotesGiven,
        count(distinct b.Id) as TotalBadges,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
AnswerDelays as (
    select
        q.Id as QuestionId,
        q.CreationDate as QuestionCreationDate,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreationDate,
        extract(epoch from (a.CreationDate - q.CreationDate))/3600 as HoursToAnswer
    from Posts q
    join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and a.CreationDate > q.CreationDate
),
AnswerDelayStats as (
    select
        QuestionId,
        min(HoursToAnswer) as MinHoursToAnswer,
        max(HoursToAnswer) as MaxHoursToAnswer,
        avg(HoursToAnswer) as AvgHoursToAnswer,
        percentile_cont(0.5) within group (order by HoursToAnswer) as MedianHoursToAnswer
    from AnswerDelays
    group by QuestionId
),
CombinedResults as (
    select
        tq.QuestionId,
        tq.Title,
        tq.QuestionCreationDate,
        tq.QuestionScore,
        tq.QuestionViewCount,
        tq.AnswerId,
        tq.AnswerScore,
        tq.AnswerCreationDate,
        tq.AnswerOwnerUserId,
        tq.AnswerOwnerDisplayName,
        ad.MinHoursToAnswer,
        ad.MaxHoursToAnswer,
        ad.AvgHoursToAnswer,
        ad.MedianHoursToAnswer,
        cq.CloseDate,
        cq.CloseReason,
        cq.ClosedByUserName,
        ur.ReputationRank,
        ur.LocationReputationRank,
        ps.QuestionCount,
        ps.AnswerCount,
        ps.AvgScore,
        ps.MaxScore,
        ps.TotalQuestionViews,
        uac.TotalPosts,
        uac.TotalComments,
        uac.TotalUpVotesGiven,
        uac.TotalDownVotesGiven,
        uac.TotalBadges,
        ubc.BadgeCount filter (where ubc.Class = 1) as GoldBadges,
        ubc.BadgeCount filter (where ubc.Class = 2) as SilverBadges,
        ubc.BadgeCount filter (where ubc.Class = 3) as BronzeBadges
    from TopQuestionsWithAnswers tq
    left join AnswerDelayStats ad on ad.QuestionId = tq.QuestionId
    left join ClosedQuestionsWithReasons cq on cq.PostId = tq.QuestionId
    left join UserReputationRanks ur on ur.Id = tq.AnswerOwnerUserId
    left join PostScoreStats ps on ps.OwnerUserId = tq.AnswerOwnerUserId
    left join UserActivitySummary uac on uac.UserId = tq.AnswerOwnerUserId
    left join UserBadgeCounts ubc on ubc.UserId = tq.AnswerOwnerUserId
    order by tq.QuestionScore desc nulls last, tq.AnswerScore desc nulls last
    limit 100
)
select
    cr.QuestionId,
    cr.Title,
    cr.QuestionCreationDate,
    cr.QuestionScore,
    cr.QuestionViewCount,
    cr.AnswerId,
    cr.AnswerScore,
    cr.AnswerCreationDate,
    cr.AnswerOwnerUserId,
    coalesce(cr.AnswerOwnerDisplayName, 'Anonymous') as AnswerOwnerDisplayName,
    round(cr.MinHoursToAnswer::numeric,2) as MinHoursToAnswer,
    round(cr.MaxHoursToAnswer::numeric,2) as MaxHoursToAnswer,
    round(cr.AvgHoursToAnswer::numeric,2) as AvgHoursToAnswer,
    round(cr.MedianHoursToAnswer::numeric,2) as MedianHoursToAnswer,
    cr.CloseDate,
    cr.CloseReason,
    cr.ClosedByUserName,
    cr.ReputationRank,
    cr.LocationReputationRank,
    cr.QuestionCount,
    cr.AnswerCount,
    round(cr.AvgScore::numeric,2) as AvgScore,
    cr.MaxScore,
    cr.TotalQuestionViews,
    cr.TotalPosts,
    cr.TotalComments,
    cr.TotalUpVotesGiven,
    cr.TotalDownVotesGiven,
    cr.TotalBadges,
    coalesce(cr.GoldBadges, 0) as GoldBadges,
    coalesce(cr.SilverBadges, 0) as SilverBadges,
    coalesce(cr.BronzeBadges, 0) as BronzeBadges,
    -- Complex string expression combining tags from the question (if any)
    (
        select string_agg(distinct trim(both '<>' from unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'))), ', ' order by 1)
        from Posts p
        where p.Id = cr.QuestionId and p.Tags is not null
    ) as QuestionTags,
    -- Complex NULL logic: if user has no badges, show 'No badges', else show badge counts
    case
        when cr.TotalBadges is null or cr.TotalBadges = 0 then 'No badges'
        else format('G:%s, S:%s, B:%s', coalesce(cr.GoldBadges,0), coalesce(cr.SilverBadges,0), coalesce(cr.BronzeBadges,0))
    end as BadgeSummary
from CombinedResults cr
where cr.AnswerScore is not null
and (cr.CloseDate is null or cr.CloseDate > cr.QuestionCreationDate + interval '30 days')
and cr.QuestionScore > 0
order by cr.QuestionScore desc, cr.AnswerScore desc;