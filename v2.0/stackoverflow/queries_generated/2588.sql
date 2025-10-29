-- {"query": "2588.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1638} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        0 as Level,
        array[t.TagName] as TagPath
    from Tags t
    where not t.IsModeratorOnly = 1

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.TagPath || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id > r.Id and not t.IsModeratorOnly = 1 and t.TagName <> all(r.TagPath)
    where r.Level < 2
),
RecentHighActivityQuestions as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName as OwnerName,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.CommentCount, 0) as CommentCount,
        row_number() over (partition by u.Id order by p.CreationDate desc) as UserRecentPostRank
    from Posts p
    join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 -- questions only
    and p.Score > 10
    and p.ViewCount > 1000
    and p.CreationDate > current_date - interval '180 days'
),
BadgeCountAgg as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
UserStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        coalesce(bc.GoldBadges, 0) as GoldBadges,
        coalesce(bc.SilverBadges, 0) as SilverBadges,
        coalesce(bc.BronzeBadges, 0) as BronzeBadges,
        (u.UpVotes - u.DownVotes)::float / nullif(u.Reputation,0) as VoteToReputationRatio
    from Users u
    left join BadgeCountAgg bc on bc.UserId = u.Id
),
LatestAnswerPerQuestion as (
    select distinct on (p.ParentId)
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score,
        p.CreationDate,
        p.OwnerUserId
    from Posts p
    where p.PostTypeId = 2 -- answers
    order by p.ParentId, p.CreationDate desc
),
QuestionCommentsAgg as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        bool_or(c.UserId is null) as HasAnonymousComment
    from Comments c
    group by c.PostId
),
DuplicatesAndLinks as (
    select
        pl.PostId,
        count(case when lt.Name = 'Duplicate' then 1 end) as DuplicateCount,
        count(case when lt.Name = 'Linked' then 1 end) as LinkedCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
HighImpactQuestions as (
    select
        q.Id,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        COALESCE(d.LinkCount, 0) as LinkedCount,
        COALESCE(d.DuplicateCount, 0) as DuplicateCount,
        q.Tags,
        q.OwnerUserId,
        u.DisplayName as OwnerName,
        ac.CommentCount,
        ac.HasAnonymousComment,
        la.AnswerId as LatestAnswerId,
        la.OwnerUserId as LatestAnswerUserId,
        la.Score as LatestAnswerScore,
        la.CreationDate as LatestAnswerDate
    from Posts q
    left join DuplicatesAndLinks d on q.Id = d.PostId
    left join QuestionCommentsAgg ac on q.Id = ac.PostId
    left join LatestAnswerPerQuestion la on q.Id = la.QuestionId
    left join Users u on q.OwnerUserId = u.Id
    where q.PostTypeId = 1
    and q.Score > 20
    and q.ViewCount > 5000
)
select 
    hq.Id as QuestionId,
    hq.Title,
    hq.ViewCount,
    hq.Score,
    hq.AnswerCount,
    hq.FavoriteCount,
    hq.DuplicateCount,
    hq.LinkedCount,
    hq.CommentCount,
    hq.HasAnonymousComment,
    COALESCE(us.GoldBadges, 0) as OwnerGoldBadges,
    COALESCE(us.SilverBadges, 0) as OwnerSilverBadges,
    COALESCE(us.BronzeBadges, 0) as OwnerBronzeBadges,
    us.Reputation as OwnerReputation,
    us.VoteToReputationRatio,
    hq.OwnerName,
    laq.Id as LatestAnswerId,
    laq.Score as LatestAnswerScore,
    laq.CreationDate as LatestAnswerDate,
    laUser.DisplayName as LatestAnswerUser,
    count(distinct ph.Id) filter (
        where ph.PostHistoryTypeId in (10, 12, 19) and ph.PostId = hq.Id -- Closed, Deleted, Protected
    ) as SpecialHistoryActions,
    string_agg(distinct substring(t.TagName from 1 for 5), ',') as ShortTagNames,
    sum(case 
        when v.VoteTypeId = 2 then 1 -- UpMod
        when v.VoteTypeId = 3 then -1 -- DownMod
        else 0 end) as VoteScoreDelta,
    row_number() over (partition by hq.OwnerUserId order by hq.CreationDate desc) as OwnerRecentQuestionRank
from HighImpactQuestions hq
join UserStats us on us.UserId = hq.OwnerUserId
left join Posts laq on laq.Id = hq.LatestAnswerId
left join Users laUser on laUser.Id = laq.OwnerUserId
left join PostHistory ph on ph.PostId = hq.Id
left join Votes v on v.PostId = hq.Id and v.CreationDate > hq.CreationDate - interval '90 days'
left join Tags t on position(concat('<', t.TagName, '>') in coalesce(hq.Tags, '')) > 0
group by 
    hq.Id, hq.Title, hq.ViewCount, hq.Score, hq.AnswerCount, hq.FavoriteCount, hq.DuplicateCount, hq.LinkedCount, hq.CommentCount, hq.HasAnonymousComment,
    us.GoldBadges, us.SilverBadges, us.BronzeBadges, us.Reputation, us.VoteToReputationRatio, hq.OwnerName,
    laq.Id, laq.Score, laq.CreationDate, laUser.DisplayName,
    hq.OwnerUserId, hq.CreationDate
having 
    count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 12) < 5 -- Less than 5 deletions
order by VoteScoreDelta desc, hq.ViewCount desc
limit 100;