with RecursiveBadges as (
    select
        b.Id,
        b.UserId,
        b.Name,
        b.Date,
        b.Class,
        b.TagBased,
        u.DisplayName,
        row_number() over (partition by b.UserId order by b.Date desc, b.Name) as BadgeRank
    from Badges b
    join Users u on u.Id = b.UserId
    where b.Date > date '2020-01-01'
), FilteredPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        case when p.ClosedDate is null then 0 else 1 end as IsClosed
    from Posts p
    where p.PostTypeId = 1 and p.CreationDate > date '2019-01-01'
), PostVotesAgg as (
    select
        v.PostId,
        count(case when vt.Name = 'UpMod' then 1 end) as UpVotes,
        count(case when vt.Name = 'DownMod' then 1 end) as DownVotes,
        count(case when vt.Name = 'Favorite' then 1 end) as Favorites
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
), DetailedTaggedQuestions as (
    select
        fp.Id,
        fp.Title,
        fp.Tags,
        fp.Score,
        fp.ViewCount,
        fp.AnswerCount,
        fp.FavoriteCount,
        fv.UpVotes,
        fv.DownVotes,
        fv.Favorites,
        fp.IsClosed,
        array_length(string_to_array(substring(fp.Tags from 2 for length(fp.Tags) - 2), '><'), 1) as TagCount,
        u.Reputation,
        rb.Name as RecentBadge,
        rb.Class as RecentBadgeClass
    from FilteredPosts fp
    left join PostVotesAgg fv on fv.PostId = fp.Id
    left join Users u on u.Id = fp.OwnerUserId
    left join RecursiveBadges rb on rb.UserId = fp.OwnerUserId and rb.BadgeRank = 1
    where u.Reputation > 1000
), MostLinkedPosts as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as LinkCount
    from PostLinks pl
    group by pl.PostId
), PostCommentsCount as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
), FinalPosts as (
    select
        dtq.Id,
        dtq.Title,
        dtq.Tags,
        dtq.Score,
        dtq.ViewCount,
        dtq.AnswerCount,
        dtq.FavoriteCount,
        dtq.UpVotes,
        dtq.DownVotes,
        dtq.Favorites,
        dtq.IsClosed,
        dtq.TagCount,
        dtq.Reputation,
        dtq.RecentBadge,
        dtq.RecentBadgeClass,
        ml.LinkCount,
        coalesce(pc.CommentCount, 0) as CommentCount,
        pc.LastCommentDate,
        -- rank partition uses expression; include it as-is but ensure deterministic grouping earlier
        rank() over (partition by dtq.Reputation / nullif(dtq.TagCount,1) order by dtq.Score desc) as RankWithinReputationPerTag
    from DetailedTaggedQuestions dtq
    left join MostLinkedPosts ml on ml.PostId = dtq.Id
    left join PostCommentsCount pc on pc.PostId = dtq.Id
    where dtq.TagCount between 2 and 5
), CorrelatedSubQuery as (
    select
        p.Id,
        p.Title,
        -- Count of edits by users other than the owner
        (select count(*) from PostHistory ph where ph.PostId = p.Id and ph.UserId is not null and ph.UserId <> p.OwnerUserId) as ExternalEditCount,
        -- complicated complex predicate expression measuring time since creation to last editing
        extract(epoch from coalesce(ph2.LastEdit, p.CreationDate) - p.CreationDate) as EditTimeSpanInSecs
    from (
        select
            fp.Id,
            fp.Title,
            fp.OwnerUserId,
            fp.CreationDate
        from FilteredPosts fp
    ) p
    left join lateral (
        select max(p2.LastEditDate) as LastEdit
        from Posts p2
        where p2.Id = p.Id and p2.LastEditDate is not null
    ) ph2 on true
)
select
    fp.Id,
    fp.Title,
    fp.Reputation,
    fp.Score,
    fp.ViewCount,
    fp.AnswerCount,
    fp.FavoriteCount,
    fp.UpVotes,
    fp.DownVotes,
    fp.Favorites,
    fp.CommentCount,
    fp.LinkCount,
    fp.IsClosed,
    fp.RecentBadge,
    fp.RecentBadgeClass,
    fp.TagCount,
    csub.ExternalEditCount,
    csub.EditTimeSpanInSecs,
    case
        when fp.IsClosed = 1 then coalesce(nullif(fp.FavoriteCount, 0), 0) * ln(1 + fp.AnswerCount)
        else fp.Score * sqrt(fp.ViewCount + 1) / nullif(fp.TagCount, 1)
    end as WeightedScore,
    -- split tags into individual tags; use standard-compatible approach where possible
    coalesce(string_agg(distinct t.tag, ', '), 'No Tags') as IndividualTags,
    fp.RankWithinReputationPerTag
from FinalPosts fp
join CorrelatedSubQuery csub on csub.Id = fp.Id
left join lateral (
    select regexp_split_to_table(fp.Tags, '><') as tag
) t on true
where (fp.Reputation + fp.ViewCount) > 5000
and fp.RecentBadgeClass is not null
group by
    fp.Id,
    fp.Title,
    fp.Reputation,
    fp.Score,
    fp.ViewCount,
    fp.AnswerCount,
    fp.FavoriteCount,
    fp.UpVotes,
    fp.DownVotes,
    fp.Favorites,
    fp.CommentCount,
    fp.LinkCount,
    fp.IsClosed,
    fp.RecentBadge,
    fp.RecentBadgeClass,
    fp.TagCount,
    csub.ExternalEditCount,
    csub.EditTimeSpanInSecs,
    fp.RankWithinReputationPerTag,
    fp.Tags
order by WeightedScore desc
limit 25;