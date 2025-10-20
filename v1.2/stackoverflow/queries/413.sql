with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        sum(v.VoteCount) as TotalVotesReceived,
        row_number() over (order by u.Reputation desc, u.Id) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId in (2,3)
        group by PostId
    ) v on v.PostId = p.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserBadgeStats as (
    select
        b.UserId,
        count(*) as TotalBadges,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        max(case when cast(b.TagBased as integer) = 1 then 1 else 0 end) as HasTagBasedBadge
    from Badges b
    group by b.UserId
),
TopQuestions as (
    select
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as QuestionRank
    from Posts p
    where p.PostTypeId = 1
),
AcceptedAnswerScores as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.Id as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerDisplayName
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount,
        q.CreationDate as QuestionCreationDate,
        coalesce(a.AnswerScore, 0) as AcceptedAnswerScore,
        a.AnswerOwnerUserId,
        a.AnswerOwnerDisplayName,
        (select count(*) from Posts ans where ans.ParentId = q.Id and ans.PostTypeId = 2) as AnswerCount,
        (select count(*) from Comments c where c.PostId = q.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 3) as DownVotes,
        case when q.ClosedDate is not null then 1 else 0 end as IsClosed
    from Posts q
    left join AcceptedAnswerScores a on a.QuestionId = q.Id
    where q.PostTypeId = 1
),
PostHistoryCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
),
UserActivityWithBadges as (
    select
        ua.*,
        coalesce(ubs.TotalBadges, 0) as TotalBadges,
        coalesce(ubs.GoldBadges, 0) as GoldBadges,
        coalesce(ubs.SilverBadges, 0) as SilverBadges,
        coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
        coalesce(ubs.HasTagBasedBadge, 0) as HasTagBasedBadge
    from RecursiveUserActivity ua
    left join UserBadgeStats ubs on ubs.UserId = ua.UserId
),
UserQuestionStats as (
    select
        u.UserId,
        u.DisplayName,
        count(q.QuestionId) as TotalQuestions,
        sum(q.AnswerCount) as TotalAnswersReceived,
        avg(q.QuestionScore) as AvgQuestionScore,
        max(q.QuestionScore) as MaxQuestionScore,
        sum(case when q.IsClosed = 1 then 1 else 0 end) as ClosedQuestions,
        string_agg(distinct pr.CloseReasonName, ', ') as CloseReasons
    from UserActivityWithBadges u
    left join QuestionAnswerStats q on q.OwnerUserId = u.UserId
    left join PostHistoryCloseReasons pr on pr.PostId = q.QuestionId
    group by u.UserId, u.DisplayName
),
UserRankedQuestions as (
    select
        q.*,
        row_number() over (partition by q.OwnerUserId order by q.Score desc, q.ViewCount desc) as RankByScore
    from Posts q
    where q.PostTypeId = 1
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as OwnerDisplayName,
        q.Title as QuestionTitle,
        lkt.Name as LinkTypeName
    from PostLinks pl
    inner join LinkTypes lkt on lkt.Id = pl.LinkTypeId
    left join Posts q on q.Id = pl.PostId and q.PostTypeId = 1
    left join Users u on u.Id = q.OwnerUserId
    where pl.LinkTypeId = 3
),
UserCommentsWithSentiment as (
    select
        c.UserId,
        c.PostId,
        c.CreationDate,
        c.Text,
        length(c.Text) as TextLength,
        case
            when c.Text ilike '%thank%' or c.Text ilike '%thanks%' then 'Positive'
            when c.Text ilike '%error%' or c.Text ilike '%fail%' then 'Negative'
            else 'Neutral'
        end as Sentiment
    from Comments c
    where c.UserId is not null
),
FinalUserSummary as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.TotalVotesReceived,
        ua.UserRank,
        ubs.TotalBadges,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.HasTagBasedBadge,
        uqs.TotalQuestions,
        uqs.TotalAnswersReceived,
        uqs.AvgQuestionScore,
        uqs.MaxQuestionScore,
        uqs.ClosedQuestions,
        uqs.CloseReasons,
        count(distinct dc.PostId) filter (where dc.Sentiment = 'Positive') as PositiveComments,
        count(distinct dc.PostId) filter (where dc.Sentiment = 'Negative') as NegativeComments,
        count(distinct dc.PostId) filter (where dc.Sentiment = 'Neutral') as NeutralComments
    from UserActivityWithBadges ua
    left join UserQuestionStats uqs on uqs.UserId = ua.UserId
    left join UserCommentsWithSentiment dc on dc.UserId = ua.UserId
    left join UserBadgeStats ubs on ubs.UserId = ua.UserId
    group by
        ua.UserId, ua.DisplayName, ua.Reputation, ua.QuestionsAsked, ua.AnswersGiven, ua.CommentsMade, ua.TotalVotesReceived, ua.UserRank,
        ubs.TotalBadges, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.HasTagBasedBadge,
        uqs.TotalQuestions, uqs.TotalAnswersReceived, uqs.AvgQuestionScore, uqs.MaxQuestionScore, uqs.ClosedQuestions, uqs.CloseReasons
)
select
    fus.UserId,
    fus.DisplayName,
    fus.Reputation,
    fus.QuestionsAsked,
    fus.AnswersGiven,
    fus.CommentsMade,
    fus.TotalVotesReceived,
    fus.UserRank,
    fus.TotalBadges,
    fus.GoldBadges,
    fus.SilverBadges,
    fus.BronzeBadges,
    fus.HasTagBasedBadge,
    fus.TotalQuestions,
    fus.TotalAnswersReceived,
    round(cast(fus.AvgQuestionScore as numeric), 2) as AvgQuestionScore,
    fus.MaxQuestionScore,
    fus.ClosedQuestions,
    coalesce(fus.CloseReasons, 'None') as CloseReasons,
    fus.PositiveComments,
    fus.NegativeComments,
    fus.NeutralComments,
    case
        when fus.Reputation > 10000 and fus.GoldBadges > 0 then 'Expert'
        when fus.Reputation between 1000 and 10000 then 'Intermediate'
        else 'Beginner'
    end as UserLevel,
    concat_ws(' | ',
        coalesce(fus.DisplayName, 'Unknown'),
        'Reputation: ' || fus.Reputation,
        'Badges: ' || fus.TotalBadges,
        'Questions: ' || fus.QuestionsAsked,
        'Answers: ' || fus.AnswersGiven
    ) as UserSummary
from FinalUserSummary fus
where fus.QuestionsAsked > 10
order by fus.Reputation desc, fus.TotalBadges desc
limit 100;