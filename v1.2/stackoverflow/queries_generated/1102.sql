-- {"query": "1102.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1548} 
with RecursiveTagCounts as (
    select 
        t.Id as TagId,
        t.TagName,
        p.Id as PostId,
        coalesce(p.Score,0) as PostScore,
        row_number() over (partition by t.Id order by p.Score desc nulls last, p.CreationDate asc) as TagPostRank,
        p.CreationDate
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 1 -- Only questions
    where t.IsModeratorOnly = 0
), TopTagPosts as (
    select TagId, TagName, PostId, PostScore, TagPostRank, CreationDate
    from RecursiveTagCounts
    where TagPostRank <= 10
), UserBadgeStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) filter (where b.Class=1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class=2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class=3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
), PostVoteAggregates as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId=2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId=3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId=8 then coalesce(v.BountyAmount,0) else 0 end) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
), LatestComments as (
    select distinct on (c.PostId)
        c.PostId,
        c.Id as CommentId,
        c.Text as CommentText,
        c.CreationDate as CommentDate,
        u.DisplayName as CommentUser
    from Comments c
    left join Users u on u.Id = c.UserId
    order by c.PostId, c.CreationDate desc
), QuestionStats as (
    select 
        p.Id, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount,
        p.AnswerCount, p.FavoriteCount, p.ClosedDate,
        p.OwnerUserId,
        pv.UpVotes, pv.DownVotes, pv.TotalBounty,
        lc.CommentId, lc.CommentText, lc.CommentDate, lc.CommentUser,
        ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
    from Posts p
    left join PostVoteAggregates pv on pv.PostId = p.Id
    left join LatestComments lc on lc.PostId = p.Id
    left join UserBadgeStats ub on ub.UserId = p.OwnerUserId
    where p.PostTypeId = 1
),
DuplicatedQuestions as (
    select pl.PostId, pl.RelatedPostId, pl.LinkTypeId,
        pq.Title as QuestionTitle,
        pr.Title as RelatedQuestionTitle
    from PostLinks pl
    join Posts pq on pq.Id = pl.PostId and pq.PostTypeId = 1
    join Posts pr on pr.Id = pl.RelatedPostId and pr.PostTypeId = 1
    where pl.LinkTypeId = 3 -- Duplicate
),
RankedAnswers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.CreationDate,
        a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as RankByScore
    from Posts a
    where a.PostTypeId = 2
),
AnswerAggregates as (
    select
        q.Id as QuestionId,
        count(a.AnswerId) as AnswerCount,
        max(case when a.RankByScore=1 then a.Score else null end) as TopAnswerScore
    from Posts q
    left join RankedAnswers a on a.QuestionId = q.Id
    where q.PostTypeId = 1
    group by q.Id
),
FinalOutput as (
    select
        qs.Id as QuestionId,
        qs.Title,
        coalesce(qs.GoldBadges,0) as OwnerGoldBadges,
        coalesce(qa.AnswerCount,0) as NumAnswers,
        qa.TopAnswerScore,
        qs.Score as QuestionScore,
        qs.ViewCount,
        qs.FavoriteCount,
        qs.UpVotes,
        qs.DownVotes,
        qs.TotalBounty,
        -- String manipulation: Extract first tag
        substring(split_part(qs.Tags, '><', 1) from 2) as FirstTag,
        -- Calculate age in days
        (current_timestamp - qs.CreationDate) / interval '1 day' as AgeDays,
        -- Null logic: Is closed recently (within 30 days)
        case when qs.ClosedDate is not null and qs.ClosedDate > current_timestamp - interval '30 day' then 1 else 0 end as IsRecentlyClosed,
        -- Latest comment details, with fallbacks
        coalesce(qs.CommentUser, 'Anonymous') as LastCommentUser,
        coalesce(substring(qs.CommentText from 1 for 100), '[No Comment]') as LastCommentSnippet,
        qs.GoldBadges + qs.SilverBadges + qs.BronzeBadges as TotalBadges,
        -- Correlated subquery: Number of duplicates for this question
        (select count(*) from DuplicatedQuestions dq where dq.PostId = qs.Id) as DuplicateCount,
        -- Window function: rank questions by score within their first tag group
        rank() over (partition by substring(split_part(qs.Tags, '><', 1) from 2) order by qs.Score desc nulls last) as RankByTagScore
    from QuestionStats qs
    left join AnswerAggregates qa on qa.QuestionId = qs.Id
    where qs.Score > 5 and qs.ViewCount > 100 -- filter moderate popularity
    order by RankByTagScore, qs.Score desc, qs.CreationDate asc
    limit 100
)
select * from FinalOutput
union all
select
    ttp.PostId as QuestionId,
    ttp.TagName || ' Popular Question' as Title,
    0 as OwnerGoldBadges,
    0 as NumAnswers,
    ttp.PostScore as TopAnswerScore,
    ttp.PostScore as QuestionScore,
    0 as ViewCount,
    0 as FavoriteCount,
    0 as UpVotes,
    0 as DownVotes,
    0 as TotalBounty,
    ttp.TagName as FirstTag,
    0 as AgeDays,
    0 as IsRecentlyClosed,
    'System' as LastCommentUser,
    'Popular Tag Question' as LastCommentSnippet,
    0 as TotalBadges,
    0 as DuplicateCount,
    1 as RankByTagScore
from TopTagPosts ttp
where ttp.TagPostRank = 1
order by QuestionId desc
limit 20;