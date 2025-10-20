with Recursive RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.OwnerUserId,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        u.Reputation as OwnerReputation,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc, p.CreationDate asc) as RankWithinType
    from
        Posts p
        left join Users u on p.OwnerUserId = u.Id
    where
        p.PostTypeId in (1, 2) -- Questions or Answers
        and p.Score is not null
), LatestCommentsPerPost as (
    select distinct on (c.PostId)
        c.PostId,
        c.Id as CommentId,
        c.Score as CommentScore,
        c.CreationDate as CommentDate,
        c.Text as CommentText,
        c.UserId as CommentUserId
    from
        Comments c
    order by
        c.PostId,
        c.Score desc,
        c.CreationDate desc
), RecentlyActiveUsers as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        row_number() over (order by u.LastAccessDate desc) as rn,
        greatest(
          extract(epoch from timestamp '2024-10-01 12:34:56')::bigint - extract(epoch from u.CreationDate)::bigint,
          1
        ) / 86400.0 as AccountAgeInDays
    from
        Users u
    where
        u.Reputation >= 1000
), BadgeSummarySemi as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadgeNames
    from
        Badges b
    group by
        b.UserId
), PopularTagFrequentlyQuestions as (
    select
        tag as Tag,
        count(*) as QuestionCount,
        avg(p.ViewCount) as AvgViewCount,
        max(p.Score) as max_score,
        min(p.Score) as min_score
    from (
      select
        p.Id,
        p.ViewCount,
        p.Score,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as tag
      from Posts p
      where p.PostTypeId = 1
        and p.Tags is not null
    ) p
    group by
        tag
    having
        count(*) > 20
), PostsTaggedWithPopular as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        t.Tag as PopularTag
    from
        Posts p
        join PopularTagFrequentlyQuestions t
          on exists (
            select 1
            from unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as tag(val)
            where tag.val = t.Tag
          )
)
select
    rp.Id,
    rp.PostTypeId,
    rp.Title,
    rp.Score,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.Tags,
    rp.AcceptedAnswerId,
    rp.OwnerReputation,
    rp.RankWithinType,
    lc.CommentId,
    lc.CommentScore,
    lc.CommentDate,
    lc.CommentText,
    lc.CommentUserId,
    rau.UserId as RecentUserId,
    rau.DisplayName as RecentUserDisplayName,
    rau.Reputation as RecentUserReputation,
    rau.CreationDate as RecentUserCreationDate,
    rau.LastAccessDate as RecentUserLastAccessDate,
    rau.AccountAgeInDays,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.DistinctBadgeNames,
    pt.QuestionCount,
    pt.AvgViewCount,
    pt.max_score,
    pt.min_score,
    ppop.PopularTag
from
    RankedPosts rp
    left join LatestCommentsPerPost lc on rp.Id = lc.PostId
    left join PostsTaggedWithPopular ppop on rp.Id = ppop.Id
    left join PopularTagFrequentlyQuestions pt on ppop.PopularTag = pt.Tag
    left join RecentlyActiveUsers rau on rp.OwnerUserId = rau.UserId
    left join BadgeSummarySemi bs on rp.OwnerUserId = bs.UserId
group by
    rp.Id,
    rp.PostTypeId,
    rp.Title,
    rp.Score,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.Tags,
    rp.AcceptedAnswerId,
    rp.OwnerReputation,
    rp.RankWithinType,
    lc.CommentId,
    lc.CommentScore,
    lc.CommentDate,
    lc.CommentText,
    lc.CommentUserId,
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.CreationDate,
    rau.LastAccessDate,
    rau.AccountAgeInDays,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.DistinctBadgeNames,
    pt.QuestionCount,
    pt.AvgViewCount,
    pt.max_score,
    pt.min_score,
    ppop.PopularTag
order by
    rp.PostTypeId,
    rp.RankWithinType;