-- {"query": "329.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1930} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    where b.TagBased = 0
),
TopBadges as (
    select UserId, DisplayName, BadgeName, Class
    from RecursiveUserBadges
    where BadgeRank <= 3
),
PostScores as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        coalesce(p.AcceptedAnswerId, -1) as AcceptedAnswerId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as UserPostRank
    from Posts p
    where p.PostTypeId in (1, 2) -- Questions and Answers
),
PostAnswerCounts as (
    select 
        p.ParentId as QuestionId,
        count(*) filter (where p.Score > 0) as PositiveAnswers,
        count(*) filter (where p.Score <= 0) as NonPositiveAnswers
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
QuestionWithAnswers as (
    select 
        q.Id,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount,
        q.CreationDate,
        coalesce(pac.PositiveAnswers, 0) as PositiveAnswers,
        coalesce(pac.NonPositiveAnswers, 0) as NonPositiveAnswers,
        q.AcceptedAnswerId
    from Posts q
    left join PostAnswerCounts pac on pac.QuestionId = q.Id
    where q.PostTypeId = 1
),
UserActivity as (
    select 
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as TotalUpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as TotalDownVotesGiven,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
DuplicateQuestions as (
    select distinct pl.PostId as DuplicateQuestionId, pl.RelatedPostId as OriginalQuestionId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
),
ClosedQuestions as (
    select ph.PostId, crt.Name as CloseReason, ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
),
QuestionStats as (
    select 
        q.Id,
        q.Title,
        q.Tags,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        coalesce(dq.OriginalQuestionId, null) as OriginalQuestionId,
        coalesce(cq.CloseReason, 'Open') as CloseReason,
        cq.CloseDate,
        row_number() over (partition by q.OwnerUserId order by q.Score desc) as UserTopQuestionRank
    from Posts q
    left join DuplicateQuestions dq on dq.DuplicateQuestionId = q.Id
    left join ClosedQuestions cq on cq.PostId = q.Id
    where q.PostTypeId = 1
),
UserQuestionSummary as (
    select 
        ua.Id as UserId,
        ua.DisplayName,
        count(distinct qs.Id) as TotalQuestions,
        count(distinct case when qs.CloseReason != 'Open' then qs.Id end) as ClosedQuestions,
        count(distinct case when qs.OriginalQuestionId is not null then qs.Id end) as DuplicateQuestions,
        avg(qs.Score) filter (where qs.Score is not null) as AvgQuestionScore,
        max(qs.ViewCount) as MaxQuestionViews,
        min(qs.CreationDate) as FirstQuestionDate,
        max(qs.CreationDate) as LastQuestionDate
    from UserActivity ua
    left join QuestionStats qs on qs.OwnerUserId = ua.Id
    group by ua.Id, ua.DisplayName
),
RankedAnswers as (
    select 
        p.Id,
        p.ParentId as QuestionId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2
),
AnswerWithAcceptedFlag as (
    select 
        ra.*,
        case when ra.Id = q.AcceptedAnswerId then 1 else 0 end as IsAccepted
    from RankedAnswers ra
    join Posts q on q.Id = ra.QuestionId
),
AnswerStats as (
    select 
        a.OwnerUserId as UserId,
        count(*) as TotalAnswers,
        sum(case when a.IsAccepted = 1 then 1 else 0 end) as AcceptedAnswers,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore
    from AnswerWithAcceptedFlag a
    group by a.OwnerUserId
),
UserReputationGrowth as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        lead(u.Reputation) over (order by u.CreationDate) - u.Reputation as NextUserReputationDiff,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
),
UserSummary as (
    select 
        ua.Id,
        ua.DisplayName,
        ua.TotalPosts,
        ua.TotalComments,
        ua.TotalUpVotesGiven,
        ua.TotalDownVotesGiven,
        coalesce(usq.TotalQuestions, 0) as TotalQuestions,
        coalesce(usq.ClosedQuestions, 0) as ClosedQuestions,
        coalesce(usq.DuplicateQuestions, 0) as DuplicateQuestions,
        coalesce(asn.TotalAnswers, 0) as TotalAnswers,
        coalesce(asn.AcceptedAnswers, 0) as AcceptedAnswers,
        coalesce(asn.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(usq.AvgQuestionScore, 0) as AvgQuestionScore,
        ur.ReputationRank
    from UserActivity ua
    left join UserQuestionSummary usq on usq.UserId = ua.Id
    left join AnswerStats asn on asn.UserId = ua.Id
    left join UserReputationGrowth ur on ur.UserId = ua.Id
)
select 
    us.DisplayName,
    us.TotalPosts,
    us.TotalComments,
    us.TotalUpVotesGiven,
    us.TotalDownVotesGiven,
    us.TotalQuestions,
    us.ClosedQuestions,
    us.DuplicateQuestions,
    us.TotalAnswers,
    us.AcceptedAnswers,
    round(us.AvgAnswerScore, 2) as AvgAnswerScore,
    round(us.AvgQuestionScore, 2) as AvgQuestionScore,
    us.ReputationRank,
    tb.BadgeName,
    tb.Class as BadgeClass,
    case 
        when us.TotalQuestions > 0 then 
            (select count(*) from Posts p where p.OwnerUserId = us.Id and p.PostTypeId = 1 and p.Score > (select avg(Score) from Posts where PostTypeId = 1))
        else 0
    end as QuestionsAboveAvgScore,
    case 
        when us.TotalAnswers > 0 then 
            (select count(*) from Posts p where p.OwnerUserId = us.Id and p.PostTypeId = 2 and p.Score > (select avg(Score) from Posts where PostTypeId = 2))
        else 0
    end as AnswersAboveAvgScore,
    concat_ws(' | ', 
        coalesce(us.DisplayName, 'Unknown User'), 
        'Posts:', us.TotalPosts, 
        'Questions:', us.TotalQuestions, 
        'Answers:', us.TotalAnswers) as UserSummaryString
from UserSummary us
left join TopBadges tb on tb.UserId = us.Id
where us.TotalPosts > 50
order by us.ReputationRank asc, us.TotalPosts desc
limit 100;