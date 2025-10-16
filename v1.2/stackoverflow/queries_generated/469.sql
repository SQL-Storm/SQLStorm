-- {"query": "469.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1341} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews,
        row_number() over (order by t.Count desc, t.TagName) as TagRank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        count(c.Id) as CommentCount,
        sum(v.VoteTypeId = 2::smallint)::int as UpVotes,
        sum(v.VoteTypeId = 3::smallint)::int as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.Title, p.Tags
),
FilteredPosts as (
    select
        p.*,
        u.DisplayName as OwnerName,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.Location,
        u.AboutMe,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        bs.TagBasedBadges
    from PostActivityWindow p
    left join Users u on u.Id = p.OwnerUserId
    left join UserBadgeSummary bs on bs.UserId = u.Id
    where p.PostTypeId = 1
      and p.Score > 5
      and p.ViewCount > 1000
      and (p.Tags is not null and length(p.Tags) > 0)
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3
),
CloseReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as smallint)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
UserRecentActivity as (
    select
        u.Id as UserId,
        max(p.CreationDate) as LastPostDate,
        max(ph.CreationDate) as LastEditDate,
        max(v.CreationDate) as LastVoteDate,
        max(c.CreationDate) as LastCommentDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id
)
select
    fp.Id as QuestionId,
    fp.Title,
    fp.OwnerUserId,
    fp.OwnerName,
    fp.Reputation,
    fp.Score,
    fp.ViewCount,
    fp.CommentCount,
    fp.FavoriteCount,
    fp.GoldBadges,
    fp.SilverBadges,
    fp.BronzeBadges,
    fp.TagBasedBadges,
    fp.Tags,
    dtc.TagRank,
    dtc.Count as TagGlobalCount,
    coalesce(crc.CloseCount, 0) as TotalCloseVotes,
    crc.CloseReason,
    dl.RelatedPostId as DuplicateOf,
    ua.LastPostDate,
    ua.LastEditDate,
    ua.LastVoteDate,
    ua.LastCommentDate,
    case
        when fp.Score > 50 and fp.ViewCount > 10000 then 'High Impact'
        when fp.Score between 10 and 50 then 'Medium Impact'
        else 'Low Impact'
    end as ImpactCategory,
    length(fp.Title) as TitleLength,
    length(fp.Tags) - length(replace(fp.Tags, '><', '')) + 1 as TagCount,
    substring(fp.AboutMe from 1 for 50) as UserAboutSnippet,
    (select count(*) from Posts a where a.ParentId = fp.Id and a.Score > fp.Score / 2) as HighScoringAnswersCount,
    (select avg(v.VoteTypeId = 2::smallint)::float from Votes v where v.PostId = fp.Id) as AvgUpvoteRatio
from FilteredPosts fp
left join RecursiveTagCounts dtc on dtc.TagName = substring(fp.Tags from 2 for position('>' in substring(fp.Tags from 2)) - 1)
left join CloseReasonCounts crc on crc.PostId = fp.Id
left join DuplicateLinks dl on dl.PostId = fp.Id
left join UserRecentActivity ua on ua.UserId = fp.OwnerUserId
where fp.OwnerUserId is not null
order by fp.Score desc, fp.ViewCount desc
limit 100;