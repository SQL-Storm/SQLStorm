-- {"query": "2186.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1079} 
with RecursiveUserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        b.Class,
        count(b.Id) as BadgeCount,
        row_number() over(partition by u.Id order by b.Class) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, b.Class
), LatestAnswerScores as (
    select
        p.OwnerUserId,
        p.ParentId as QuestionId,
        p.Id as AnswerId,
        p.Score,
        row_number() over(partition by p.ParentId order by p.Score desc, p.CreationDate desc) as answer_rank
    from Posts p
    where p.PostTypeId = 2 -- answers only
), TopAnswers as (
    select
        las.*
    from LatestAnswerScores las
    where las.answer_rank = 1
), QuestionCloseInfo as (
    select
        ph.PostId,
        cr.Name as CloseReason,
        max(ph.CreationDate) as LastClosedAt
    from PostHistory ph
    inner join CloseReasonTypes cr on cast(ph.Comment as int) = cr.Id
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, cr.Name
), QuestionsWithTopAnswerAndCloseReason as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        ta.AnswerId,
        ta.Score as TopAnswerScore,
        q.Tags,
        coalesce(qci.CloseReason, 'Not Closed') as CloseReason,
        q.ViewCount,
        q.FavoriteCount,
        q.AnswerCount,
        q.CommentCount
    from Posts q
    left join TopAnswers ta on ta.QuestionId = q.Id
    left join QuestionCloseInfo qci on qci.PostId = q.Id
    where q.PostTypeId = 1
), RankedUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        max(p.CreationDate) as LastPostDate,
        count(distinct b.Id) as BadgesEarned,
        row_number() over(order by count(distinct p.Id) desc) as activity_rank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id and b.Class = 1 -- gold badges only
    group by u.Id, u.DisplayName
    having count(distinct p.Id) > 0
), UserCommentTextStats as (
    select
        c.UserId,
        avg(length(c.Text)) as AvgCommentLength,
        sum(case when c.Text is null or trim(c.Text) = '' then 1 else 0 end) as EmptyCommentsCount,
        count(*) as TotalComments
    from Comments c
    group by c.UserId
), FinalUserSummary as (
    select
        ru.UserId,
        ru.DisplayName,
        ru.QuestionsAsked,
        ru.AnswersGiven,
        ru.CommentsMade,
        ru.BadgesEarned,
        coalesce(uc.AvgCommentLength, 0) as AvgCommentLength,
        coalesce(uc.EmptyCommentsCount, 0) as EmptyCommentsCount,
        ru.LastPostDate,
        ru.activity_rank
    from RankedUserActivity ru
    left join UserCommentTextStats uc on uc.UserId = ru.UserId
)
select
    q.QuestionId,
    q.Title,
    q.QuestionScore,
    q.TopAnswerScore,
    q.ViewCount,
    q.FavoriteCount,
    q.AnswerCount,
    q.CommentCount,
    q.CloseReason,
    r.DisplayName as QuestionOwner,
    r.QuestionsAsked,
    r.AnswersGiven,
    r.CommentsMade,
    r.BadgesEarned,
    r.AvgCommentLength,
    r.EmptyCommentsCount,
    row_number() over(partition by q.CloseReason order by q.ViewCount desc) as RankWithinCloseReason,
    case when q.Tags is not null then 
        upper(regexp_replace(split_part(split_part(q.Tags, '><', 1), '><', 1), '[^a-zA-Z0-9]', '_', 'g'))
    else 'No_Tags' end as PrimaryTagNorm
from QuestionsWithTopAnswerAndCloseReason q
left join FinalUserSummary r on r.UserId = q.OwnerUserId
where q.QuestionScore > 5
  and q.ViewCount > 1000
order by q.CloseReason, RankWithinCloseReason
limit 100;