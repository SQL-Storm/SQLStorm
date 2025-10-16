-- {"query": "309.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1500} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.Reputation,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    left join Posts p on p.Tags like '%' || '<' || t.TagName || '>' || '%'
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
TopTagPosts as (
    select
        Id,
        TagName,
        PostId,
        Score,
        ViewCount,
        OwnerUserId,
        Reputation
    from RecursiveTagCounts
    where rn <= 5
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostVoteStats as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
PostCommentStats as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
UserActivityRank as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) as TotalPosts,
        count(distinct ph.Id) as TotalEdits,
        rank() over (order by count(distinct p.Id) desc, u.Reputation desc) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostWithCloseInfo as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where p.PostTypeId = 1
),
DuplicatePosts as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
),
UserPostSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(ub.GoldBadges,0) as GoldBadges,
        coalesce(ub.SilverBadges,0) as SilverBadges,
        coalesce(ub.BronzeBadges,0) as BronzeBadges,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join UserBadgeCounts ub on ub.UserId = u.Id
    group by u.Id, u.DisplayName, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, u.Reputation, u.CreationDate, u.LastAccessDate
)
select
    ttp.TagName,
    ttp.PostId,
    ttp.Score,
    ttp.ViewCount,
    ttp.OwnerUserId,
    us.DisplayName as OwnerName,
    us.Reputation as OwnerReputation,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    pvs.UpVotes,
    pvs.DownVotes,
    pvs.Favorites,
    pcs.CommentCount,
    pcs.LastCommentDate,
    pwi.CloseReason,
    pwi.CloseDate,
    dup.RelatedPostId as DuplicateOfPostId,
    dup.RelatedPostTitle as DuplicateOfPostTitle,
    uar.ActivityRank,
    us.QuestionCount,
    us.AnswerCount,
    us.Reputation,
    us.CreationDate,
    us.LastAccessDate,
    case
        when pwi.CloseReason is not null then 'Closed'
        when dup.RelatedPostId is not null then 'Duplicate'
        else 'Open'
    end as PostStatus,
    length(coalesce(ttp.TagName, '')) + length(coalesce(ttp.PostId::text, '')) as DummyStringLength,
    (select count(*) from Comments c2 where c2.PostId = ttp.PostId and c2.Score > 0) as PositiveCommentsCount,
    (select avg(v.BountyAmount) from Votes v where v.PostId = ttp.PostId and v.BountyAmount is not null) as AvgBountyAmount,
    row_number() over (partition by ttp.TagName order by ttp.Score desc, ttp.ViewCount desc) as RankWithinTag
from TopTagPosts ttp
left join Users us on us.Id = ttp.OwnerUserId
left join UserBadgeCounts ubc on ubc.UserId = ttp.OwnerUserId
left join PostVoteStats pvs on pvs.PostId = ttp.PostId
left join PostCommentStats pcs on pcs.PostId = ttp.PostId
left join PostWithCloseInfo pwi on pwi.Id = ttp.PostId
left join DuplicatePosts dup on dup.PostId = ttp.PostId
left join UserActivityRank uar on uar.Id = ttp.OwnerUserId
left join UserPostSummary us2 on us2.UserId = ttp.OwnerUserId
where ttp.Score > 0
order by ttp.TagName, RankWithinTag
limit 100;