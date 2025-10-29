-- {"query": "2056.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1381}
with recursive TagHierarchy(tagid, parentid, level) as (
    select t.Id, cast(null as integer), 1
    from Tags t
    where t.IsRequired = true
    union all
    select t.Id, th.tagid, th.level + 1
    from Tags t
    join TagHierarchy th on t.WikiPostId = th.tagid
),
TopUsers as (
    select u.Id, u.DisplayName, u.Reputation,
           dense_rank() over (order by u.Reputation desc) as rep_rank
    from Users u
    where u.Reputation > 1000
),
RecentActivePosts as (
    select p.Id, p.PostTypeId, p.CreationDate, p.Score, p.OwnerUserId, p.Tags,
           row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn
    from Posts p
    where p.CreationDate > (cast('2024-10-01' as date) - cast(90 as integer) * interval '1' day)
),
UserBadgeCounts as (
    select b.UserId,
           sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
           sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
           sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostLinkAggregates as (
    select pl.PostId,
           count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount,
           count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
QuestionsWithAcceptedAnswerScores as (
    select q.Id, q.Title, q.Tags, q.Score as question_score,
           a.Id as answer_id, coalesce(a.Score,0) as answer_score,
           (coalesce(a.Score,0) - q.Score) as score_diff
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
UserCommentsOnRecentAnswers as (
    select c.UserId, count(*) as CommentCountOnRecentAnswers
    from Comments c
    join RecentActivePosts rap on c.PostId = rap.Id and rap.PostTypeId = 2
    group by c.UserId
),
TopUserActivity as (
    select u.Id as UserId, u.DisplayName,
           count(distinct p.Id) as TotalPosts,
           sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
           sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCount,
           coalesce(ub.GoldBadges,0) as GoldBadges,
           coalesce(ub.SilverBadges,0) as SilverBadges,
           coalesce(ub.BronzeBadges,0) as BronzeBadges,
           coalesce(uc.CommentCountOnRecentAnswers,0) as CommentsOnAnswers,
           max(p.Score) as MaxPostScore,
           avg(case when p.Score > 0 then p.Score end) as AvgPositivePostScore
    from TopUsers u
    left join Posts p on p.OwnerUserId = u.Id
    left join UserBadgeCounts ub on ub.UserId = u.Id
    left join UserCommentsOnRecentAnswers uc on uc.UserId = u.Id
    group by u.Id, u.DisplayName, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, uc.CommentCountOnRecentAnswers
),
QuestionsClosedRecently as (
    select ph.PostId, ph.CreationDate as CloseDate,
           crt.Name as CloseReason
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where ph.CreationDate > (cast('2024-10-01' as date) - cast(30 as integer) * interval '1' day)
),
QuestionDuplicatesCTE as (
    select distinct pl.PostId as DuplicateQuestionId, pl.RelatedPostId as OriginalQuestionId
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id and lt.Name = 'Duplicate'
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
),
HighlyVotedAnswersWithComments as (
    select a.Id as AnswerId, a.ParentId as QuestionId, a.Score, count(c.Id) as CommentCount,
           string_agg(distinct coalesce(u.DisplayName, 'anon'), ', ') as Commenters
    from Posts a
    left join Comments c on c.PostId = a.Id
    left join Users u on u.Id = c.UserId
    where a.PostTypeId = 2 and a.Score > 50
    group by a.Id, a.ParentId, a.Score
),
FinalData as (
    select tu.DisplayName as UserName, tu.Reputation, tu.rep_rank,
           tua.TotalPosts, tua.QuestionsCount, tua.AnswersCount,
           tua.GoldBadges, tua.SilverBadges, tua.BronzeBadges,
           tua.CommentsOnAnswers,
           qwa.question_score, qwa.answer_score, qwa.score_diff,
           pga.LinkedCount, pga.DuplicateCount,
           qc.CloseDate, qc.CloseReason,
           hdac.AnswerId, hdac.CommentCount, hdac.Commenters
    from TopUserActivity tua
    join TopUsers tu on tu.Id = tua.UserId
    left join QuestionsWithAcceptedAnswerScores qwa on qwa.Id = (
        select p.Id from Posts p where p.OwnerUserId = tu.Id and p.PostTypeId = 1 order by p.CreationDate desc limit 1
    )
    left join PostLinkAggregates pga on pga.PostId = qwa.Id
    left join QuestionsClosedRecently qc on qc.PostId = qwa.Id
    left join HighlyVotedAnswersWithComments hdac on hdac.QuestionId = qwa.Id
    where tu.rep_rank <= 10
)
select *
from FinalData
order by Reputation desc, TotalPosts desc
limit 20;