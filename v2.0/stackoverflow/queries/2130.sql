-- {"query": "2130.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1527} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(b.BadgeCount, 0) as BadgeCount,
        coalesce(p.QuestionCount, 0) as QuestionCount,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(v.UpVotesCount, 0) as UpVotesCount,
        coalesce(v.DownVotesCount, 0) as DownVotesCount,
        -- Calculate activity span in days, protect against nulls
        extract(epoch from coalesce(u.LastAccessDate, u.CreationDate) - u.CreationDate)/86400 as ActivitySpanDays
    from Users u
    left join (
        select UserId, count(*) as BadgeCount
        from Badges
        group by UserId
    ) b on u.Id = b.UserId
    left join (
        select OwnerUserId,
            count(case when PostTypeId = 1 then 1 end) as QuestionCount,
            count(case when PostTypeId = 2 then 1 end) as AnswerCount
        from Posts
        where OwnerUserId is not null and OwnerUserId <> -1
        group by OwnerUserId
    ) p on u.Id = p.OwnerUserId
    left join (
        select
            UserId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotesCount,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotesCount
        from Votes
        where UserId is not null
        group by UserId
    ) v on u.Id = v.UserId
    where u.Reputation > 1000
),
TopTagsByActivity as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        -- Posts tagged with this tag, joining with PostTags expanded
        count(distinct p.Id) as TotalPosts,
        sum(p.Score) as TotalScore,
        max(p.ViewCount) as MaxViewCount
    from Tags t
    join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    group by t.Id, t.TagName, t.Count
    order by TotalPosts desc
    limit 50
),
UserTopBadges as (
    select
        b.UserId,
        b.Name as BadgeName,
        row_number() over (partition by b.UserId order by b.Date desc) as rn
    from Badges b
    where b.Class = 1 -- Gold badges only
),
UserLastComments as (
    select
        c.UserId,
        c.PostId,
        c.CreationDate,
        c.Text,
        row_number() over (partition by c.UserId order by c.CreationDate desc) as rn
    from Comments c
    where c.UserId is not null
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        count(a.Id) as AnswerCount,
        avg(coalesce(a.Score, 0)) as AvgAnswerScore,
        max(coalesce(a.Score, 0)) as MaxAnswerScore,
        sum(case when v.VoteTypeId = 1 then 1 else 0 end) as AcceptedAnswersCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Votes v on v.PostId = a.Id and v.VoteTypeId = 1
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score
    having count(a.Id) > 3 and avg(coalesce(a.Score, 0)) > 2
),
DuplicateQuestionGroups as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        pl.CreationDate as LinkDate,
        row_number() over (partition by pl.PostId order by pl.CreationDate desc) as rn
    from PostLinks pl
    where pl.LinkTypeId = 3 -- Duplicate
),
UserDetailedStats as (
    select 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.BadgeCount,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.UpVotesCount,
        ua.DownVotesCount,
        ua.ActivitySpanDays,
        utb.TagName as FavoriteTag,
        ub.BadgeName as LatestGoldBadge,
        ulc.Text as LatestCommentText,
        qs.QuestionCountOver10Answers,
        coalesce(dq.DuplicateCount, 0) as DuplicateQuestionsCount
    from RecursiveUserActivity ua
    left join lateral (
        select t.TagName
        from TopTagsByActivity t
        join Posts p on p.Tags like concat('%<', t.TagName, '>%')
        where p.OwnerUserId = ua.UserId
        group by t.TagName
        order by count(*) desc nulls last
        limit 1
    ) utb on true
    left join UserTopBadges ub on ub.UserId = ua.UserId and ub.rn = 1
    left join UserLastComments ulc on ulc.UserId = ua.UserId and ulc.rn = 1
    left join lateral (
        select count(*) as QuestionCountOver10Answers
        from Posts p
        where p.OwnerUserId = ua.UserId and p.PostTypeId = 1 and p.AnswerCount > 10
    ) qs on true
    left join lateral (
        select count(distinct dq.DuplicateQuestionId) as DuplicateCount
        from DuplicateQuestionGroups dq
        join Posts p on p.Id = dq.DuplicateQuestionId and p.OwnerUserId = ua.UserId
    ) dq on true
)
select
    uds.UserId,
    uds.DisplayName,
    uds.Reputation,
    uds.BadgeCount,
    uds.QuestionCount,
    uds.AnswerCount,
    uds.UpVotesCount,
    uds.DownVotesCount,
    round(uds.ActivitySpanDays,2) as ActivityDays,
    uds.FavoriteTag,
    uds.LatestGoldBadge,
    substring(uds.LatestCommentText from 1 for 80) as LatestCommentSnippet,
    uds.QuestionCountOver10Answers,
    uds.DuplicateQuestionsCount,
    -- Calculate engagement score using weighted factors with null-safe coalesce
    round(
        0.4 * coalesce(uds.Reputation,0)/1000 +
        0.3 * coalesce(uds.BadgeCount,0) +
        0.15 * coalesce(uds.QuestionCountOver10Answers,0) +
        0.1 * coalesce(uds.UpVotesCount,0)/100 +
        0.05 * coalesce(uds.DuplicateQuestionsCount,0)
    , 4) as EngagementScore
from UserDetailedStats uds
where uds.QuestionCount > 0 or uds.AnswerCount > 0
order by EngagementScore desc, Reputation desc
limit 100;