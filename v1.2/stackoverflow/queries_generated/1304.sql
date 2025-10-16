-- {"query": "1304.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1268} 
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
    where b.Date > '2020-01-01'
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
    where p.PostTypeId = 1 and p.CreationDate > '2019-01-01'
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
        dtq.*,
        ml.LinkCount,
        coalesce(pc.CommentCount, 0) as CommentCount,
        pc.LastCommentDate,
        -- window function applied partition by OwnerUserId to rank by Score desc
        rank() over (partition by dtq.Reputation / nullif(TagCount,1) order by dtq.Score desc) as RankWithinReputationPerTag
    from DetailedTaggedQuestions dtq
    left join MostLinkedPosts ml on ml.PostId = dtq.Id
    left join PostCommentsCount pc on pc.PostId = dtq.Id
    where dtq.TagCount between 2 and 5
), CorrelatedSubQuery as (
    select
        p.Id,
        p.Title,
        # Count of edits by users other than the owner
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
        select max(LastEditDate) as LastEdit
        from Posts p2
        where p2.Id = p.Id and p2.LastEditDate is not null
    ) ph2 on true
    left join LATERAL (
        select count(*) as EditCount from PostHistory ph where ph.PostId = p.Id and ph.UserId is not null and ph.UserId <> p.OwnerUserId
    ) ph on true
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
        when fp.IsClosed = 1 then coalesce(nullif(fp.FavoriteCount, 0), 0) * log(1 + fp.AnswerCount)
        else fp.Score * sqrt(fp.ViewCount + 1) / nullif(fp.TagCount, 1)
    end as WeightedScore,
    -- more complicated string logic with coalesce to handle NULL tags
    coalesce(string_agg(distinct regexp_split_to_table(fp.Tags, '><'), ', '), 'No Tags') as IndividualTags,
    -- Beside use of CTE window rank, also returning the rank
    fp.RankWithinReputationPerTag
from FinalPosts fp
join CorrelatedSubQuery csub on csub.Id = fp.Id
where (fp.Reputation + fp.ViewCount) > 5000
and fp.RecentBadgeClass is not null
order by WeightedScore desc
limit 25;