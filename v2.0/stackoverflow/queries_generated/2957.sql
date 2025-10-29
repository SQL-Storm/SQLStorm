-- {"query": "2957.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1586} 
with RecursiveUserStats as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        coalesce(badge_counts.GoldBadges, 0) as GoldBadges,
        coalesce(badge_counts.SilverBadges, 0) as SilverBadges,
        coalesce(badge_counts.BronzeBadges, 0) as BronzeBadges,
        row_number() over (order by u.Reputation desc, u.Views desc nulls last) as UserRank
    from Users u
    left join (
        select 
            UserId,
            sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
            sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
            sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
        from Badges
        group by UserId
    ) badge_counts on u.Id = badge_counts.UserId
    where u.Reputation > 1000
),
TopUserPosts as (
    select
        p.OwnerUserId,
        p.PostTypeId,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        count(distinct c.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVoteCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVoteCount,
        string_agg(distinct lt.Name, ', ' order by lt.Name) as LinkTypesToRelatedPosts,
        (
            select string_agg(distinct lh.Name, ', ')
            from PostHistory ph
            join PostHistoryTypes lh on ph.PostHistoryTypeId = lh.Id
            where ph.PostId = p.Id and ph.UserId = p.OwnerUserId
        ) as OwnerHistoryTypes
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
    where p.OwnerUserId in (select Id from RecursiveUserStats)
    group by p.OwnerUserId, p.PostTypeId, p.Id, p.Score, p.ViewCount, p.CreationDate, p.Title
),
AggregatedUserActivity as (
    select
        rus.Id as UserId,
        rus.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as TotalComments,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        coalesce(sum(v.BountyAmount), 0) as TotalBounty,
        min(p.CreationDate) as FirstPostDate,
        max(p.LastActivityDate) as LastActivityDate
    from RecursiveUserStats rus
    left join Posts p on p.OwnerUserId = rus.Id
    left join Comments c on c.UserId = rus.Id
    left join Votes v on v.UserId = rus.Id and v.BountyAmount is not null
    group by rus.Id, rus.DisplayName
),
QuestionsWithDupesAndClose as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.Tags,
        cl.RelatedPostId as DuplicateOfQuestionId,
        cr.Name as CloseReason,
        ph.CloseDate,
        ph.Text as CloseMetadata,
        row_number() over (partition by q.Id order by ph.CreationDate desc) as CloseEventRank
    from Posts q
    left join PostLinks cl on cl.PostId = q.Id and cl.LinkTypeId = 3 -- Duplicates
    left join PostHistory ph on ph.PostId = q.Id and ph.PostHistoryTypeId = 10 -- Post Closed
    left join CloseReasonTypes cr on cr.Id = cast(ph.Comment as int)
    where q.PostTypeId = 1
),
LatestClosedQuestions AS (
    select * from QuestionsWithDupesAndClose where CloseEventRank = 1
),
AnswersWithAcceptedFlag AS (
    select
        a.Id,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        case when q.AcceptedAnswerId = a.Id then 1 else 0 end as IsAcceptedAnswer,
        q.Title as QuestionTitle,
        q.Tags as QuestionTags,
        u.DisplayName as OwnerName
    from Posts a
    inner join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
UserAnswerRanking as (
    select
        a.*,
        rank() over (partition by a.OwnerUserId order by a.Score desc, a.CreationDate) as AnswerRank
    from AnswersWithAcceptedFlag a
),
BadgeRecentCounts as (
    select
        b.UserId,
        b.Name as BadgeName,
        count(*) filter (where b.Date > current_date - interval '30 days') as RecentBadgeCount
    from Badges b
    group by b.UserId, b.Name
)
select
    rus.UserRank,
    rus.DisplayName,
    aua.QuestionCount,
    aua.AnswerCount,
    aua.TotalComments,
    aua.MaxQuestionScore,
    aua.MaxAnswerScore,
    aua.TotalBounty,
    coalesce(bc.RecentBadgeCount,0) as RecentBadgeCount,
    lcq.Title as LatestClosedQuestionTitle,
    lcq.CloseReason,
    lcq.DuplicateOfQuestionId,
    (case when lcq.DuplicateOfQuestionId is not null then 'Yes' else 'No' end) as IsDuplicate,
    ua.AnswerRank,
    ua.Score as TopAnswerScore,
    ua.IsAcceptedAnswer,
    ua.QuestionTitle as TopAnswerQuestionTitle,
    ua.OwnerName as TopAnswerOwner,
    -- Complex string expression combining tags and location info with NULL logic
    concat_ws(
        ' | ',
        coalesce(rus.Location, 'Unknown Location'),
        substring(regexp_replace(coalesce(ua.QuestionTags, ''), '[<>]', ','), 1, 100),
        case when rus.Views > 100000 then 'Highly Viewed Profile' else 'Normal Profile' end
    ) as LocationAndTagsSummary
from RecursiveUserStats rus
left join AggregatedUserActivity aua on aua.UserId = rus.Id
left join LatestClosedQuestions lcq on lcq.CreationDate > current_date - interval '365 days' and lcq.DuplicateOfQuestionId is not null
left join UserAnswerRanking ua on ua.OwnerUserId = rus.Id and ua.AnswerRank = 1
left join BadgeRecentCounts bc on bc.UserId = rus.Id
where rus.UserRank <= 100
order by rus.UserRank, ua.Score desc
limit 200;