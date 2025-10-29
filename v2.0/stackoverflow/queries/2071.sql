-- {"query": "2071.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1255}
with recursive UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (order by u.Reputation desc nulls last) as RepRank
    from
        Users u
        left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
), PostScores as (
    select
        p.Id as PostId,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        -- Complex string calculation: count of tags from Tags varchar
        array_length(string_to_array(substring(p.Tags from 2 for coalesce(nullif(length(p.Tags), 0)-2, 0)), '><'),1) as TagCount,
        -- Calculate weighted score by Score and ViewCount with null logic
        coalesce(p.Score,0)*1.5 + coalesce(p.ViewCount,0)*0.05 as WeightedScore,
        -- Calculate age of post in days
        extract(epoch from (timestamp '2024-10-01 12:34:56' - p.CreationDate))/86400 as AgeDays
    from
        Posts p
    where
        p.PostTypeId in (1,2) -- Only Questions and Answers
), PostAnswers as (
    select
        q.Id as QuestionId,
        count(a.Id) as TotalAnswers,
        max(a.Score) as MaxAnswerScore,
        sum(a.Score) as SumAnswerScores
    from
        Posts q
        left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where
        q.PostTypeId = 1
    group by q.Id
), TopPosts as (
    select
        ps.*,
        pac.TotalAnswers,
        pac.MaxAnswerScore,
        pac.SumAnswerScores,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.RepRank
    from
        PostScores ps
        left join PostAnswers pac on pac.QuestionId = ps.PostId
        left join UserBadgeCounts ubc on ubc.UserId = ps.OwnerUserId
), RankedPosts as (
    select
        tp.*,
        row_number() over (partition by tp.PostTypeId order by tp.WeightedScore desc nulls last) as PostRank,
        rank() over (partition by tp.PostTypeId order by tp.AgeDays) as AgeRank,
        dense_rank() over (order by tp.OwnerUserId) as OwnerRank
    from
        TopPosts tp
), DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pt.Name as PostTypeName,
        lt.Name as LinkTypeName
    from
        PostLinks pl
        join LinkTypes lt on lt.Id = pl.LinkTypeId
        join Posts p on p.Id = pl.PostId
        join PostTypes pt on pt.Id = p.PostTypeId
    where
        lt.Name = 'Duplicate'
), RecentComments as (
    select
        c.PostId,
        c.UserId,
        c.CreationDate,
        c.Text,
        row_number() over (partition by c.PostId order by c.CreationDate desc) as CommentRank
    from Comments c
), LatestCommentTexts as (
    select
        rc.PostId,
        rc.Text as LatestCommentText
    from
        RecentComments rc
    where
        rc.CommentRank = 1
)
select
    rp.PostId,
    rp.Title,
    rp.PostTypeId,
    pt.Name as PostTypeName,
    rp.Score,
    rp.ViewCount,
    rp.TagCount,
    rp.WeightedScore,
    rp.AgeDays,
    rp.TotalAnswers,
    rp.MaxAnswerScore,
    rp.SumAnswerScores,
    rp.GoldBadges,
    rp.SilverBadges,
    rp.BronzeBadges,
    rp.RepRank,
    rp.PostRank,
    rp.AgeRank,
    rp.OwnerRank,
    coalesce(dl.RelatedPostId, -1) as DuplicateRelatedPostId,
    dl.LinkTypeName as DuplicateLinkType,
    lc.LatestCommentText,
    case
        when rp.Score > 10 and rp.ViewCount > 1000 then 'Popular'
        when rp.Score <= 10 and rp.Score >= 0 then 'Normal'
        when rp.Score < 0 then 'Controversial'
        else 'Unknown'
    end as PopularityCategory,
    concat_ws(' | ', rp.Title, coalesce(lc.LatestCommentText, 'No recent comments')) as TitleWithComment,
    (select count(*)
     from Posts pa
     where pa.ParentId = rp.PostId
       and pa.CreationDate > rp.CreationDate
       and pa.OwnerUserId = rp.OwnerUserId) as SubsequentAnswersByOwner
from
    RankedPosts rp
    join PostTypes pt on pt.Id = rp.PostTypeId
    left join DuplicateLinks dl on dl.PostId = rp.PostId
    left join LatestCommentTexts lc on lc.PostId = rp.PostId
where
    (rp.GoldBadges > 0 or rp.SilverBadges > 2 or rp.BronzeBadges > 5)
    and rp.PostRank <= 50
order by
    rp.PostTypeId,
    rp.WeightedScore desc,
    rp.AgeDays asc;