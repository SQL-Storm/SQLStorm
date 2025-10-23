-- {"query": "429.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1436} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.CreationDate as PostCreationDate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
FilteredUserPosts as (
    select *
    from RecursiveUserActivity
    where RecentPostRank <= 5
),
PostVotesAgg as (
    select
        p.Id as PostId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        count(v.Id) as TotalVotes,
        sum(case when v.VoteTypeId = 8 then v.BountyAmount else 0 end) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
PostCommentsAgg as (
    select
        c.PostId,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as Commenters
    from Comments c
    group by c.PostId
),
UserBadgeStats as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as UniqueBadges
    from Badges b
    group by b.UserId
),
PostWithDetails as (
    select
        fup.UserId,
        fup.DisplayName,
        fup.Reputation,
        fup.Location,
        fup.PostId,
        fup.PostTypeId,
        fup.Score,
        fup.ViewCount,
        fup.Title,
        fup.Tags,
        fup.PostCreationDate,
        pva.UpVotes,
        pva.DownVotes,
        pva.TotalVotes,
        pva.TotalBounty,
        pca.CommentCount,
        pca.LastCommentDate,
        pca.Commenters,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.UniqueBadges,
        -- Calculate a composite popularity score with null-safe logic and string manipulation
        (coalesce(fup.Score,0) * 3 + coalesce(pva.UpVotes,0) * 2 - coalesce(pva.DownVotes,0) + coalesce(pca.CommentCount,0) * 1.5 + coalesce(pva.TotalBounty,0) * 4) as PopularityScore,
        -- Extract first tag from Tags string (format: <tag1><tag2>...)
        substring(fup.Tags from '<([^>]+)>') as FirstTag
    from FilteredUserPosts fup
    left join PostVotesAgg pva on pva.PostId = fup.PostId
    left join PostCommentsAgg pca on pca.PostId = fup.PostId
    left join UserBadgeStats ubs on ubs.UserId = fup.UserId
),
RankedPosts as (
    select
        *,
        rank() over (partition by UserId order by PopularityScore desc) as PopularityRank
    from PostWithDetails
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- Duplicate
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as Questions,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as Answers,
        count(distinct b.Id) as TotalBadges,
        max(p.Score) as MaxPostScore,
        min(p.CreationDate) as FirstPostDate,
        max(p.CreationDate) as LastPostDate,
        -- Days active between first and last post or 1 to avoid division by zero
        greatest(date_part('day', max(p.CreationDate) - min(p.CreationDate)),1) as ActiveDays,
        -- Average posts per day
        count(distinct p.Id)::float / greatest(date_part('day', max(p.CreationDate) - min(p.CreationDate)),1) as PostsPerDay
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 1000
    group by u.Id, u.DisplayName
)
select
    r.UserId,
    r.DisplayName,
    r.Location,
    r.PostId,
    r.PostTypeId,
    r.Title,
    r.FirstTag,
    r.Score,
    r.ViewCount,
    r.UpVotes,
    r.DownVotes,
    r.TotalVotes,
    r.TotalBounty,
    r.CommentCount,
    r.LastCommentDate,
    r.Commenters,
    r.GoldBadges,
    r.SilverBadges,
    r.BronzeBadges,
    r.UniqueBadges,
    r.PopularityScore,
    r.PopularityRank,
    uas.TotalPosts,
    uas.Questions,
    uas.Answers,
    uas.TotalBadges,
    uas.MaxPostScore,
    uas.FirstPostDate,
    uas.LastPostDate,
    uas.ActiveDays,
    round(uas.PostsPerDay,2) as PostsPerDay,
    dl.RelatedPostId,
    dl.RelatedPostTitle,
    dl.LinkCreationDate
from RankedPosts r
inner join UserActivitySummary uas on uas.UserId = r.UserId
left join DuplicateLinks dl on dl.PostId = r.PostId
where r.PopularityRank <= 3
order by r.UserId, r.PopularityRank, dl.LinkCreationDate desc nulls last;