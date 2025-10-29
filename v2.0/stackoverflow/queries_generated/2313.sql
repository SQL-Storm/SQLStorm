-- {"query": "2313.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1537} 
with RecursiveUserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Class,
        count(*) as BadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, b.Class
),
RankedPosts as (
    select
        p.Id,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc nulls last) as UserPostRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
TopUserPosts as (
    select
        rp.Id as PostId,
        rp.Title,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Tags
    from RankedPosts rp
    where rp.UserPostRank <= 3
),
PostCommentStats as (
    select
        c.PostId,
        count(c.Id) as CommentCount,
        sum(case when c.UserId is null then 0 else 1 end) as CommentsWithUsers,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as Commenters
    from Comments c
    group by c.PostId
),
AcceptedAnswerInfo as (
    select
        q.Id as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.ViewCount as AnswerViewCount,
        a.OwnerUserId as AnswerOwnerId,
        row_number() over (partition by q.Id order by a.Score desc nulls last) as AnswerRankByScore
    from Posts q
    join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.AcceptedAnswerId = a.Id
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        pl.LinkTypeId,
        l.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes l on l.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3
),
QuestionCloseHistory as (
    select
        ph.PostId,
        ph.CreationDate,
        crt.Name as CloseReason
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        sum(u.Reputation) over (order by u.Reputation desc, u.Id rows between unbounded preceding and current row) as CumulativeReputation,
        dense_rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
),
UserBadgeSummary as (
    select
        UserId,
        max(case when Class = 1 then BadgeCount else 0 end) as GoldBadges,
        max(case when Class = 2 then BadgeCount else 0 end) as SilverBadges,
        max(case when Class = 3 then BadgeCount else 0 end) as BronzeBadges
    from RecursiveUserBadgeCounts
    group by UserId
),
FilteredTags as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        coalesce(p.ViewCount, 0) as TagExcerptViewCount,
        coalesce(p.Score, 0) as TagExcerptScore
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    where t.Count > 50 -- arbitrary threshold for popular tags
),
QuestionsWithTagArrays as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        array_remove(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><'), '') as TagArray,
        p.Score,
        p.ViewCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
QuestionsWithFilteredTags as (
    select
        q.Id,
        q.Title,
        q.CreationDate,
        q.OwnerUserId,
        (select array_agg(t.TagName)
         from FilteredTags t
         where t.TagName = any(q.TagArray)
        ) as PopularTags,
        q.Score,
        q.ViewCount
    from QuestionsWithTagArrays q
)
select
    u.DisplayName,
    u.Reputation,
    ur.CumulativeReputation,
    ur.ReputationRank,
    coalesce(ubs.GoldBadges, 0) as GoldBadges,
    coalesce(ubs.SilverBadges, 0) as SilverBadges,
    coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
    p.Id as PostId,
    p.Title,
    p.PostTypeId,
    p.Score as PostScore,
    p.ViewCount as PostViews,
    coalesce(pcs.CommentCount, 0) as CommentCount,
    coalesce(pcs.CommentsWithUsers, 0) as CommentsWithUsers,
    pcs.LastCommentDate,
    pcs.Commenters,
    aa.AnswerId as AcceptedAnswerId,
    aa.AnswerScore,
    aa.AnswerViewCount,
    aa.AnswerOwnerId,
    case when qc.PostId is not null then 'Closed' else 'Open' end as PostStatus,
    qc.CloseReason,
    array_to_string(qwt.PopularTags, ', ') as PopularTags,
    case
        when p.Score > 100 then 'Hot'
        when p.Score between 50 and 100 then 'Trending'
        else 'Regular'
    end as PopularityLabel,
    translate(coalesce(p.Title, ''), 'aeiouAEIOU', '*****') as ObfuscatedTitle,
    length(coalesce(p.Body, '')) as BodyLength,
    greatest(p.Score, 0) * coalesce(p.ViewCount, 0) / greatest(1, nullif(u.Reputation,0)) as EngagementRatio
from TopUserPosts p
join Users u on u.Id = p.OwnerUserId
left join PostCommentStats pcs on pcs.PostId = p.Id
left join AcceptedAnswerInfo aa on aa.QuestionId = p.Id and p.PostTypeId = 1
left join QuestionCloseHistory qc on qc.PostId = p.Id
left join UserReputationWindow ur on ur.Id = u.Id
left join UserBadgeSummary ubs on ubs.UserId = u.Id
left join QuestionsWithFilteredTags qwt on qwt.Id = p.Id
where p.Score > (
    select avg(Score) from Posts where OwnerUserId = p.OwnerUserId and PostTypeId = p.PostTypeId
)
order by u.Reputation desc nulls last, p.Score desc nulls last, pcs.CommentCount desc nulls last
limit 100;