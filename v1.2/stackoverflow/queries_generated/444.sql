-- {"query": "444.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1656} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on t2.IsRequired = 1 and not t2.Id = any(r.Path)
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
PostScoresWithWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        dense_rank() over (partition by p.PostTypeId order by p.CreationDate desc) as RecentRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.CreationDate as QuestionCreation,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        a.CreationDate as AnswerCreation,
        u.DisplayName as QuestionOwnerName,
        au.DisplayName as AnswerOwnerName,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.TotalBadges,
        q.Tags
    from PostScoresWithWindow q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = q.OwnerUserId
    left join Users au on au.Id = a.OwnerUserId
    left join UserBadgeCounts ubc on ubc.UserId = q.OwnerUserId
    where q.PostTypeId = 1 and q.ScoreRank <= 50
),
CloseReasonsCount as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesCount,
        count(distinct ph.Comment) filter (where ph.PostHistoryTypeId = 10 and ph.Comment is not null) as DistinctCloseReasons
    from PostHistory ph
    group by ph.PostId
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.Score > 0 then 1 else 0 end) as PositiveAnswers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
CombinedResults as (
    select
        tq.QuestionId,
        tq.Title,
        coalesce(tq.QuestionOwnerName, 'Unknown') as QuestionOwner,
        tq.QuestionScore,
        tq.QuestionViews,
        tq.QuestionCreation,
        coalesce(tq.AnswerId, -1) as AnswerId,
        coalesce(tq.AnswerScore, 0) as AnswerScore,
        coalesce(tq.AnswerOwnerName, 'Unknown') as AnswerOwner,
        tq.GoldBadges,
        tq.SilverBadges,
        tq.BronzeBadges,
        tq.TotalBadges,
        crc.CloseVotesCount,
        crc.DistinctCloseReasons,
        ast.AnswerCount,
        ast.AvgAnswerScore,
        ast.MaxAnswerScore,
        ast.PositiveAnswers,
        ua.TotalPosts,
        ua.TotalComments,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        ua.Location,
        -- Complex string manipulation: extract first tag from Tags XML-like string
        substring(tq.Tags from '<([^>]+)>') as FirstTag,
        -- NULL logic: if no accepted answer, use max answer score else accepted answer score
        case 
            when a2.Id is null then coalesce(ast.MaxAnswerScore, 0)
            else (select Score from Posts where Id = (select AcceptedAnswerId from Posts where Id = tq.QuestionId))
        end as EffectiveAnswerScore
    from TopQuestionsWithAnswers tq
    left join CloseReasonsCount crc on crc.PostId = tq.QuestionId
    left join AnswerStats ast on ast.QuestionId = tq.QuestionId
    left join UserActivity ua on ua.DisplayName = tq.QuestionOwnerName
    left join Posts a2 on a2.Id = (select AcceptedAnswerId from Posts where Id = tq.QuestionId)
)
select
    cr.*,
    row_number() over (order by cr.QuestionScore desc, cr.AnswerScore desc) as RowNum,
    -- Complex predicate: filter questions with either more than 5 close votes or more than 3 distinct close reasons
    case when cr.CloseVotesCount > 5 or cr.DistinctCloseReasons > 3 then 'High Close Risk' else 'Low Close Risk' end as CloseRiskCategory,
    -- Set operator example: union of users who posted questions or answers in last 30 days
    ua_recent.UserId as RecentActiveUserId,
    ua_recent.DisplayName as RecentActiveUserName
from CombinedResults cr
left join (
    select distinct u.Id as UserId, u.DisplayName
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    where p.CreationDate >= current_date - interval '30 days'
    union
    select distinct u2.Id as UserId, u2.DisplayName
    from Users u2
    join Posts p2 on p2.OwnerUserId = u2.Id and p2.PostTypeId = 2
    where p2.CreationDate >= current_date - interval '30 days'
) ua_recent on ua_recent.UserId = cr.AnswerOwnerUserId
where cr.QuestionScore > 10
order by cr.QuestionScore desc, cr.AnswerScore desc
limit 100;