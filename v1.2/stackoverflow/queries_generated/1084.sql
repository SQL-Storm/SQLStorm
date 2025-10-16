-- {"query": "1084.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1600} 
with RankedAnswers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate) as RankByScoreDate
    from Posts a
    where a.PostTypeId = 2
), QuestionDetails as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        q.OwnerUserId,
        u.DisplayName as OwnerName,
        case when q.ClosedDate is null then 0 else 1 end as IsClosed
    from Posts q
    left join Users u on q.OwnerUserId = u.Id
    where q.PostTypeId = 1
), TopRankedAnswers as (
    select
        ra.AnswerId,
        ra.QuestionId,
        ra.Score as AnswerScore,
        ra.CreationDate as AnswerCreationDate,
        ra.OwnerUserId,
        u.DisplayName as AnswerOwnerName
    from RankedAnswers ra
    left join Users u on ra.OwnerUserId = u.Id
    where ra.RankByScoreDate = 1
), BadgeCounts as (
    select
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges
    group by UserId
), CommentCountsOnAnswers as (
    select
        p.ParentId as QuestionId,
        count(c.Id) as TotalCommentsOnAnswers
    from Posts p
    left join Comments c on p.Id = c.PostId
    where p.PostTypeId = 2
    group by p.ParentId
), DuplicateLinks as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        ph.Comment as CloseReasonCode,
        crt.Name as CloseReasonName
    from PostLinks pl
    inner join PostHistory ph on pl.PostId = ph.PostId and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where pl.LinkTypeId = 3
), UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        coalesce(sum(vb.BountyAmount),0) as TotalBountyAwarded,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes vb on vb.PostId = p.Id and vb.VoteTypeId in (8,9) -- BountyStart and BountyClose
    group by u.Id, u.DisplayName, u.Reputation
), UserRankings as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.TotalBountyAwarded,
        ua.LastPostDate,
        row_number() over (order by ua.Reputation desc, ua.QuestionsPosted desc) as RankOverall,
        row_number() over (partition by case when ua.QuestionsPosted = 0 then 0 else 1 end order by ua.Reputation desc) as RankByQuestionActivity
    from UserActivity ua
), FilteredQuestions as (
    select
        q.*,
        tr.AnswerId,
        tr.AnswerScore,
        tr.AnswerCreationDate,
        tr.AnswerOwnerName,
        bc.GoldBadges,
        bc.SilverBadges,
        bc.BronzeBadges,
        coalesce(ca.TotalCommentsOnAnswers,0) as CommentsOnAnswers
    from QuestionDetails q
    left join TopRankedAnswers tr on q.QuestionId = tr.QuestionId
    left join BadgeCounts bc on bc.UserId = q.OwnerUserId
    left join CommentCountsOnAnswers ca on ca.QuestionId = q.QuestionId
    where q.IsClosed = 0
      and q.ViewCount > 1000
      and (q.Tags ilike '%<sql>%'
           or q.Tags ilike '%<performance>%')
      and q.CreationDate < now() - interval '30 days'
)
select
    fq.QuestionId,
    fq.Title,
    fq.Score as QuestionScore,
    fq.ViewCount,
    fq.OwnerUserId,
    fq.OwnerName,
    fq.GoldBadges,
    fq.SilverBadges,
    fq.BronzeBadges,
    fq.CommentsOnAnswers,
    fq.AnswerId,
    fq.AnswerScore,
    fq.AnswerCreationDate,
    fq.AnswerOwnerName,
    dr.OriginalQuestionId as DuplicateOf,
    dr.CloseReasonName as DuplicateCloseReason,
    ur.RankOverall,
    ur.RankByQuestionActivity,
    ur.Reputation as UserReputation,
    ur.QuestionsPosted,
    ur.AnswersPosted,
    ur.TotalBountyAwarded,
    ur.LastPostDate,
    concat(
        'Q:', fq.Title, ' | Ans by ', coalesce(fq.AnswerOwnerName, 'N/A'),
        ' | UserRep:', ur.Reputation,
        ' | Badges(G/S/B):', coalesce(fq.GoldBadges,0), '/', coalesce(fq.SilverBadges,0), '/', coalesce(fq.BronzeBadges,0),
        ' | CommentsOnAnswers:', fq.CommentsOnAnswers
    ) as SummaryText
from FilteredQuestions fq
left join DuplicateLinks dr on dr.DuplicateQuestionId = fq.QuestionId
left join UserRankings ur on ur.UserId = fq.OwnerUserId
where fq.AnswerScore is not null
union
select
    fq.QuestionId,
    fq.Title,
    fq.Score as QuestionScore,
    fq.ViewCount,
    fq.OwnerUserId,
    fq.OwnerName,
    fq.GoldBadges,
    fq.SilverBadges,
    fq.BronzeBadges,
    fq.CommentsOnAnswers,
    null as AnswerId,
    null as AnswerScore,
    null as AnswerCreationDate,
    null as AnswerOwnerName,
    null as DuplicateOf,
    null as DuplicateCloseReason,
    ur.RankOverall,
    ur.RankByQuestionActivity,
    ur.Reputation as UserReputation,
    ur.QuestionsPosted,
    ur.AnswersPosted,
    ur.TotalBountyAwarded,
    ur.LastPostDate,
    concat(
        'Q:', fq.Title,
        ' | No Answers',
        ' | UserRep:', ur.Reputation,
        ' | Badges(G/S/B):', coalesce(fq.GoldBadges,0), '/', coalesce(fq.SilverBadges,0), '/', coalesce(fq.BronzeBadges,0),
        ' | CommentsOnAnswers:', fq.CommentsOnAnswers
    ) as SummaryText
from FilteredQuestions fq
left join UserRankings ur on ur.UserId = fq.OwnerUserId
where fq.AnswerId is null
order by QuestionScore desc, ViewCount desc, UserReputation desc
limit 100;