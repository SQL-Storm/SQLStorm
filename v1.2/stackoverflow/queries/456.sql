-- {"query": "456.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1394} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(v.VoteCount),0) as TotalVotesReceived,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId in (1,2) -- AcceptedByOriginator, UpMod
        group by PostId
    ) v on v.PostId = p.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopTags as (
    select
        t.TagName,
        t.Count,
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
    where t.Count > 1000
),
UserTagStats as (
    select
        rua.UserId,
        tt.TagName,
        count(distinct p.Id) as PostsInTag,
        avg(p.Score) as AvgScoreInTag,
        sum(case when p.Id = p.AcceptedAnswerId then 1 else 0 end) as AcceptedAnswersCount
    from RecursiveUserActivity rua
    join Posts p on p.OwnerUserId = rua.UserId
    join Tags t on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
    join TopTags tt on tt.TagName = t.TagName
    group by rua.UserId, tt.TagName
),
UserBadgeSummary as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges
    from Badges b
    group by b.UserId
),
PostLinkSummary as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Linked') as LinkedCount,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (10,11)) as CloseReopenEvents,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as LastCloseDate,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopenDate,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByScoreView
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    group by p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags
),
HighActivityPosts as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CloseReopenEvents,
        p.LastCloseDate,
        p.LastReopenDate,
        pl.LinkedCount,
        pl.DuplicateCount,
        ua.DisplayName as OwnerName,
        ua.Reputation as OwnerReputation
    from PostActivityWindow p
    left join PostLinkSummary pl on pl.PostId = p.Id
    left join Users ua on ua.Id = (select OwnerUserId from Posts where Id = p.Id)
    where p.CloseReopenEvents > 0
    and p.ViewCount > 10000
    and p.Score > 10
)
select
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    rua.QuestionCount,
    rua.AnswerCount,
    rua.CommentCount,
    rua.TotalVotesReceived,
    uts.TagName,
    uts.PostsInTag,
    round(uts.AvgScoreInTag,2) as AvgScoreInTag,
    uts.AcceptedAnswersCount,
    coalesce(ubs.GoldBadges,0) as GoldBadges,
    coalesce(ubs.SilverBadges,0) as SilverBadges,
    coalesce(ubs.BronzeBadges,0) as BronzeBadges,
    coalesce(ubs.DistinctBadges,0) as DistinctBadges,
    hap.Id as HighActivityPostId,
    hap.Title as HighActivityPostTitle,
    hap.Score as HighActivityPostScore,
    hap.ViewCount as HighActivityPostViews,
    hap.CloseReopenEvents as HighActivityPostCloseReopenEvents,
    hap.LastCloseDate as HighActivityPostLastCloseDate,
    hap.LastReopenDate as HighActivityPostLastReopenDate,
    hap.LinkedCount as HighActivityPostLinkedCount,
    hap.DuplicateCount as HighActivityPostDuplicateCount,
    hap.OwnerName as HighActivityPostOwnerName,
    hap.OwnerReputation as HighActivityPostOwnerReputation
from RecursiveUserActivity rua
left join UserTagStats uts on uts.UserId = rua.UserId
left join UserBadgeSummary ubs on ubs.UserId = rua.UserId
left join lateral (
    select hap.*
    from HighActivityPosts hap
    where hap.OwnerName = rua.DisplayName
    order by hap.Score desc, hap.ViewCount desc
    limit 1
) hap on true
where rua.UserRank <= 100
order by rua.Reputation desc, rua.TotalVotesReceived desc, rua.UserId
limit 100;