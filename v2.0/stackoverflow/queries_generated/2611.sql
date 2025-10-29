-- {"query": "2611.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1388} 
with recursive RecursiveRelatedPosts as (
    select pl.PostId, pl.RelatedPostId, 1 as depth
    from PostLinks pl
    where pl.LinkTypeId = 1
  union all
    select rrp.PostId, pl.RelatedPostId, rrp.depth + 1
    from RecursiveRelatedPosts rrp
      join PostLinks pl on rrp.RelatedPostId = pl.PostId
    where pl.LinkTypeId = 1 and rrp.depth < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
TopPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AcceptedAnswerId,
        coalesce(u.Reputation,0) as OwnerReputation,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1,2) -- Questions and Answers
),
PostCommentsSummary as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(c.Score) as CommentScoreSum,
        bool_or(c.Text is null or length(trim(c.Text))=0) as HasEmptyComment,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
AcceptedAnswerInfo as (
    select
        q.Id as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerName,
        rrp.RelatedPostId as RelatedAnswerId
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    left join Users u on a.OwnerUserId = u.Id
    left join RecursiveRelatedPosts rrp on a.Id = rrp.PostId and rrp.depth = 1
    where q.PostTypeId = 1
),
LatestPostHistories as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.UserDisplayName,
        ph.Comment,
        ph.Text
    from PostHistory ph
    order by ph.PostId, ph.CreationDate desc
),
TopScoredPostsWithInfo as (
    select
        tp.Id,
        tp.PostTypeId,
        tp.OwnerUserId,
        tp.Score,
        tp.ViewCount,
        tp.CreationDate,
        tp.AcceptedAnswerId,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        coalesce(pcs.CommentCount,0) as Comments,
        coalesce(pcs.CommentScoreSum,0) as CommentScores,
        coalesce(lph.PostHistoryTypeId,0) as LastPostHistoryType,
        lph.CreationDate as LastPostHistoryDate,
        case when tp.Score > 0 and coalesce(pcs.CommentScoreSum,0) > 10 then 'Popular' else 'Normal' end as PopularityStatus,
        case when tp.ViewCount = 0 then null else round(1.0 * tp.Score / tp.ViewCount, 4) end as ScoreToViewRatio,
        abs(coalesce(tp.Score,0) - coalesce(pcs.CommentScoreSum,0)) as ScoreCommentScoreDiff
    from TopPosts tp
    left join UserBadgeCounts ubc on tp.OwnerUserId = ubc.UserId
    left join PostCommentsSummary pcs on tp.Id = pcs.PostId
    left join LatestPostHistories lph on tp.Id = lph.PostId
    where tp.rn <= 100
)
select
    tspwi.Id as PostId,
    tspwi.PostTypeId,
    u.DisplayName as OwnerName,
    tspwi.OwnerUserId,
    tspwi.Score,
    tspwi.ViewCount,
    tspwi.Comments,
    tspwi.CommentScores,
    tspwi.GoldBadges,
    tspwi.SilverBadges,
    tspwi.BronzeBadges,
    tspwi.LastPostHistoryType,
    tspwi.LastPostHistoryDate,
    tspwi.PopularityStatus,
    tspwi.ScoreToViewRatio,
    tspwi.ScoreCommentScoreDiff,
    ai.AnswerId,
    ai.AnswerScore,
    ai.AnswerOwnerUserId,
    ai.AnswerOwnerName,
    (select count(1) from Votes v where v.PostId = tspwi.Id and v.VoteTypeId = 2) as UpVotesCount,
    (select count(1) from Votes v where v.PostId = tspwi.Id and v.VoteTypeId = 3) as DownVotesCount,
    (case when u.Location is not null then lower(u.Location) else 'unknown' end) as LocationNormalized,
    (case when strpos(coalesce(tspwi.LastPostHistoryType::text, ''), '10') > 0 then 1 else 0 end) as HasCloseHistory,
    string_agg(distinct coalesce(t.Name,'') , ',' order by t.Name) over (partition by tspwi.Id) as AssociatedTags,
    rank() over (partition by tspwi.PostTypeId order by tspwi.Score desc, tspwi.ViewCount desc) as RankWithinType
from TopScoredPostsWithInfo tspwi
left join AcceptedAnswerInfo ai on tspwi.Id = ai.QuestionId
left join Users u on tspwi.OwnerUserId = u.Id
left join LATERAL (
    select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as Name
    from Posts p where p.Id = tspwi.Id
) t on true
where tspwi.GoldBadges + tspwi.SilverBadges + tspwi.BronzeBadges > 5
  and tspwi.CreationDate > (current_date - interval '2 years')
order by tspwi.Score desc, tspwi.ViewCount desc
limit 50;