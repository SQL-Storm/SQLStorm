-- {"query": "482.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1462} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id as UserId,
        u.DisplayName,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 -- questions only
),
TopTagPosts as (
    select Id, TagName, Count, PostId, Score, ViewCount, CreationDate, UserId, DisplayName
    from RecursiveTagCounts
    where rn <= 5
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct b.Name) as UniqueBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        count(a.Id) as AnswerCount,
        avg(coalesce(a.Score,0)) as AvgAnswerScore,
        max(coalesce(a.Score,0)) as MaxAnswerScore,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as AnswersWithOwner
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        count(c.Id) as CommentsCount,
        sum(vt.VoteCount) as TotalVotesReceived,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select
            p.OwnerUserId,
            count(v.Id) as VoteCount
        from Votes v
        join Posts p on p.Id = v.PostId
        group by p.OwnerUserId
    ) vt on vt.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        u.DisplayName as PostOwner,
        u2.DisplayName as RelatedPostOwner
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    left join Users u on u.Id = p1.OwnerUserId
    left join Users u2 on u2.Id = p2.OwnerUserId
    where pl.LinkTypeId = 3 -- Duplicate
),
CloseReasonsCount as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.PostId, crt.Name
),
UserLatestPosts as (
    select distinct on (p.OwnerUserId)
        p.OwnerUserId as UserId,
        p.Id as PostId,
        p.Title,
        p.CreationDate
    from Posts p
    where p.OwnerUserId is not null
    order by p.OwnerUserId, p.CreationDate desc
)
select
    ttp.TagName,
    ttp.PostId,
    ttp.Score as QuestionScore,
    ttp.ViewCount as QuestionViews,
    ttp.CreationDate as QuestionCreation,
    uas.AnswerCount,
    uas.AvgAnswerScore,
    uas.MaxAnswerScore,
    uas.AnswersWithOwner,
    uaw.DisplayName as QuestionOwner,
    uaw.Reputation as OwnerReputation,
    coalesce(ubs.GoldBadges,0) as OwnerGoldBadges,
    coalesce(ubs.SilverBadges,0) as OwnerSilverBadges,
    coalesce(ubs.BronzeBadges,0) as OwnerBronzeBadges,
    coalesce(crc.CloseReason, 'Not Closed') as CloseReason,
    coalesce(crc.CloseCount, 0) as CloseVotesCount,
    dup.RelatedPostId as DuplicateOfPostId,
    dup.RelatedPostTitle as DuplicateOfTitle,
    dup.CreationDate as DuplicateLinkDate,
    uaw.LastAccessDate,
    uaw.QuestionsCount,
    uaw.AnswersCount,
    uaw.CommentsCount,
    uaw.TotalVotesReceived,
    uaw.ReputationRank,
    ulp.PostId as LatestUserPostId,
    ulp.Title as LatestUserPostTitle,
    ulp.CreationDate as LatestUserPostDate
from TopTagPosts ttp
join PostAnswerStats uas on uas.QuestionId = ttp.PostId
left join Users uaw on uaw.Id = ttp.UserId
left join UserBadgeSummary ubs on ubs.UserId = ttp.UserId
left join CloseReasonsCount crc on crc.PostId = ttp.PostId
left join DuplicateLinks dup on dup.PostId = ttp.PostId
left join UserActivityWindow uaw2 on uaw2.UserId = ttp.UserId
left join UserLatestPosts ulp on ulp.UserId = ttp.UserId
where ttp.Score > (select avg(Score) from Posts where PostTypeId = 1)
  and (ttp.ViewCount > 1000 or uas.AnswerCount > 5)
order by ttp.TagName, ttp.Score desc
limit 50;