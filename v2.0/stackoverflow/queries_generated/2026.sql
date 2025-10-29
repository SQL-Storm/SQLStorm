-- {"query": "2026.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1542} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount,0) as TotalAnswers,
        coalesce(p.ViewCount,0) as TotalViews,
        row_number() over (order by t.Count desc, t.TagName) as rn
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 1
),
UserQuestionStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct q.Id) filter (where q.PostTypeId = 1) as QuestionsAsked,
        count(distinct a.Id) filter (where a.PostTypeId = 2) as AnswersGiven,
        avg(q.Score) filter (where q.PostTypeId = 1) as AvgQuestionScore,
        avg(a.Score) filter (where a.PostTypeId = 2) as AvgAnswerScore,
        sum(vv.VoteCount) as TotalVotesReceived,
        max(q.CreationDate) filter (where q.PostTypeId = 1) as LastQuestionDate,
        max(a.CreationDate) filter (where a.PostTypeId = 2) as LastAnswerDate
    from Users u
    left join Posts q on q.OwnerUserId = u.Id and q.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join (
        select 
            PostId,
            count(*) as VoteCount
        from Votes
        where VoteTypeId in (2,3) -- UpMod or DownMod
        group by PostId
    ) vv on vv.PostId = q.Id or vv.PostId = a.Id
    group by u.Id, u.DisplayName
),
UserBadgeRankings as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 3 when b.Class = 2 then 2 else 1 end) as BadgeScore,
        dense_rank() over (order by sum(case when b.Class = 1 then 3 when b.Class = 2 then 2 else 1 end) desc) as BadgeRank
    from Badges b
    group by b.UserId
),
RecentEdits as (
    select
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ph.Comment,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    where ph.PostHistoryTypeId in (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
PostsWithLinkDuplicates as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        coalesce(lu.CountDuplicates, 0) as DuplicateCount,
        coalesce(lu.CountLinkedPosts, 0) as LinkedCount
    from Posts p
    left join (
        select 
            PostId,
            sum(case when LinkTypeId = 3 then 1 else 0 end) as CountDuplicates,
            sum(case when LinkTypeId = 1 then 1 else 0 end) as CountLinkedPosts
        from PostLinks
        group by PostId
    ) lu on lu.PostId = p.Id
),
HighImpactPosts as (
    select 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.CreationDate,
        row_number() over (order by p.Score desc, p.ViewCount desc, p.FavoriteCount desc) as PopularityRank
    from Posts p
    where p.PostTypeId = 1
),
UserRankWithWindows as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as NumQuestions,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as NumAnswers,
        sum(coalesce(p.Score, 0)) as TotalPostScore,
        rank() over (order by u.Reputation desc) as ReputationRank,
        dense_rank() over (partition by u.Location order by u.Reputation desc) as LocalRepRank,
        percent_rank() over (order by u.Reputation) as ReputationPercentile
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.NumQuestions,
    u.NumAnswers,
    u.TotalPostScore,
    ur.BadgeScore,
    ur.BadgeRank,
    u.ReputationRank,
    u.LocalRepRank,
    u.ReputationPercentile,
    t.TagName as PopularTag,
    t.Count as TagUsageCount,
    t.TotalAnswers as TagAnswerCount,
    t.TotalViews as TagViewCount,
    hip.Title as TopQuestionTitle,
    hip.Score as TopQuestionScore,
    hip.ViewCount as TopQuestionViews,
    hip.AnswerCount as TopQuestionAnswers,
    hip.FavoriteCount as TopQuestionFavorites,
    case 
        when hip.CreationDate < (current_date - interval '365 days') then 'Older Than 1 Year'
        else 'Recent'
    end as TopQuestionAge,
    pdl.DuplicateCount,
    pdl.LinkedCount,
    re.Comment as LastEditComment,
    re.CreationDate as LastEditDate
from UserRankWithWindows u
left join UserBadgeRankings ur on ur.UserId = u.Id
left join lateral (
    select t.TagName, t.Count, t.TotalAnswers, t.TotalViews 
    from RecursiveTagCounts t
    where t.rn = 1
    limit 1
) t on true
left join lateral (
    select hip.Title, hip.Score, hip.ViewCount, hip.AnswerCount, hip.FavoriteCount, hip.CreationDate 
    from HighImpactPosts hip
    join Posts p2 on p2.OwnerUserId = u.Id and p2.Id = hip.Id
    order by hip.Score desc, hip.ViewCount desc, hip.FavoriteCount desc
    limit 1
) hip on true
left join lateral (
    select pdu.DuplicateCount, pdu.LinkedCount
    from PostsWithLinkDuplicates pdu
    join Posts p3 on p3.OwnerUserId = u.Id and p3.Id = pdu.Id
    order by pdu.DuplicateCount desc, pdu.LinkedCount desc
    limit 1
) pdl on true
left join lateral (
    select re.Comment, re.CreationDate
    from RecentEdits re
    where re.UserId = u.Id
    order by re.CreationDate desc
    limit 1
) re on true
where u.NumQuestions > 0 or u.NumAnswers > 0
order by u.ReputationRank
limit 100;