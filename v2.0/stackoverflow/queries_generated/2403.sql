-- {"query": "2403.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1449} 
with RecursiveTagCTE as (
    select
        t.Id,
        t.TagName,
        t.Count,
        array_agg(p.Id) filter (where p.Id is not null) as QuestionPostIds
    from Tags t
    left join Posts p on p.PostTypeId = 1 and p.Tags like '%' || concat('<', t.TagName, '>') || '%'
    group by t.Id, t.TagName, t.Count
), 
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) as TotalBadges,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        bool_or(b.TagBased) as HasTagBasedBadge
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScoreWindow as (
    select
        p.Id,
        p.Title,
        p.ViewCount,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserPostRankByScore
    from Posts p
    where p.PostTypeId = 1
),
TopPostsWithComments as (
    select
        psw.*,
        coalesce(c.CommentCount, 0) as CommentsCount
    from PostScoreWindow psw
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = psw.Id
    where psw.UserPostRankByScore <= 10
),
CorrelatedAnswers as (
    select
        q.Id as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.ViewCount as AnswerViewCount,
        u.Reputation as AnswererReputation,
        (select count(*) from Comments c where c.PostId = a.Id) as AnswerCommentCount
    from Posts q
    join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.Score > 5 and q.ViewCount > 1000
),
PostHistoryAggregates as (
    select 
        ph.PostId,
        count(*) as TotalRevisions,
        count(distinct ph.UserId) as DistinctEditors,
        max(ph.CreationDate) as LastRevisionDate,
        sum(case when ph.PostHistoryTypeId in (10, 12) then 1 else 0 end) as CloseOrDeleteEvents
    from PostHistory ph
    group by ph.PostId
),
CandidatePosts as (
    select
        p.Id,
        p.Title,
        p.ViewCount,
        p.Score,
        p.Tags,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.HasTagBasedBadge,
        pha.TotalRevisions,
        pha.DistinctEditors,
        pha.LastRevisionDate,
        pha.CloseOrDeleteEvents,
        coalesce(pa.AnswerScore, 0) as TopAnswerScore,
        coalesce(pa.AnswerViewCount, 0) as TopAnswerViews,
        coalesce(pa.AnswererReputation, 0) as TopAnswererReputation,
        coalesce(pa.AnswerCommentCount, 0) as TopAnswerComments
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join UserBadgeSummary ub on ub.UserId = p.OwnerUserId
    left join PostHistoryAggregates pha on pha.PostId = p.Id
    left join (
        select QuestionId, max(AnswerScore) as AnswerScore, max(AnswerViewCount) as AnswerViewCount, max(AnswererReputation) as AnswererReputation, max(AnswerCommentCount) as AnswerCommentCount
        from CorrelatedAnswers
        group by QuestionId
    ) pa on pa.QuestionId = p.Id
    where p.PostTypeId = 1
),
FilteredCandidates as (
    select *
    from CandidatePosts
    where (Score + coalesce(TopAnswerScore, 0)) > 50
      and (ViewCount > 5000 or (GoldBadges > 0 and OwnerReputation > 10000))
      and CloseOrDeleteEvents = 0
      and (Tags not like '%<sql>%' or Tags is null)
),
FinalRankedPosts as (
    select
        fc.*,
        row_number() over (
            order by 
                (fc.Score + coalesce(fc.TopAnswerScore,0)) desc, 
                fc.ViewCount desc,
                fc.GoldBadges desc,
                fc.OwnerReputation desc
        ) as Rank
    from FilteredCandidates fc
)
select
    frp.Rank,
    frp.Id as PostId,
    frp.Title,
    frp.OwnerName,
    frp.OwnerReputation,
    frp.Score,
    frp.ViewCount,
    replace(coalesce(frp.Tags, ''), '><', ', ') as TagList,
    frp.GoldBadges,
    frp.SilverBadges,
    frp.BronzeBadges,
    frp.HasTagBasedBadge,
    frp.TotalRevisions,
    frp.DistinctEditors,
    frp.LastRevisionDate,
    frp.TopAnswerScore,
    frp.TopAnswerViews,
    frp.TopAnswererReputation,
    frp.TopAnswerComments,
    case when frp.ViewCount > 100000 then 'Hot' 
         when frp.ViewCount between 50000 and 100000 then 'Trending'
         else 'Normal'
    end as PopularityClassification,
    case 
        when frp.GoldBadges > 5 then 'Elite'
        when frp.GoldBadges between 1 and 5 then 'Experienced'
        else 'Novice'
    end as OwnerBadgeLevel,
    (select count(*) from PostLinks pl where pl.PostId = frp.Id and pl.LinkTypeId = 3) as DuplicateCount,
    (select count(*) from Votes v where v.PostId = frp.Id and v.VoteTypeId = 2) as Upvotes,
    (select count(*) from Votes v where v.PostId = frp.Id and v.VoteTypeId = 3) as Downvotes
from FinalRankedPosts frp
where frp.Rank <= 100
order by frp.Rank;