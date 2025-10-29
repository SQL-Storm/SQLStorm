with RecursiveUserBadges as (
    select 
        u.Id as UserId, 
        u.DisplayName,
        b.Name as BadgeName,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank,
        count(*) over (partition by u.Id) as TotalBadges,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
),
TopUserBadges as (
    select * from RecursiveUserBadges where BadgeRank <= 3
),
QuestionStats as (
    select 
        p.OwnerUserId as UserId,
        count(case when p.PostTypeId = 1 then 1 end) as QuestionsCount,
        avg(case when p.PostTypeId = 1 then p.Score end) as AvgQuestionScore,
        sum(case when p.PostTypeId = 1 then p.ViewCount else 0 end) as TotalQuestionViews,
        max(case when p.PostTypeId = 1 then p.Score end) as MaxQuestionScore
    from Posts p
    group by p.OwnerUserId
),
AnswerStats as (
    select 
        p.OwnerUserId as UserId,
        count(case when p.PostTypeId = 2 then 1 end) as AnswersCount,
        avg(case when p.PostTypeId = 2 then p.Score end) as AvgAnswerScore,
        max(case when p.PostTypeId = 2 then p.Score end) as MaxAnswerScore
    from Posts p
    group by p.OwnerUserId
),
UserActivity as (
    select 
        u.Id as UserId,
        coalesce(qs.QuestionsCount, 0) as QuestionsCount,
        coalesce(qs.AvgQuestionScore, 0) as AvgQuestionScore,
        coalesce(qs.TotalQuestionViews, 0) as TotalQuestionViews,
        coalesce(ans.AnswersCount, 0) as AnswersCount,
        coalesce(ans.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(ans.MaxAnswerScore, 0) as MaxAnswerScore,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        DENSE_RANK() over (order by u.Reputation desc) as ReputationRank,
        DENSE_RANK() over (order by coalesce(qs.AvgQuestionScore, 0) desc) as QuestionScoreRank,
        DENSE_RANK() over (order by coalesce(ans.AvgAnswerScore, 0) desc) as AnswerScoreRank
    from Users u
    left join QuestionStats qs on u.Id = qs.UserId
    left join AnswerStats ans on u.Id = ans.UserId
    where u.Reputation > 1000
),
UserCommentsWithReactions as (
    select 
        c.UserId,
        count(c.Id) as CommentsCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as CommentUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as CommentDownVotes
    from Comments c
    left join Votes v on v.PostId = c.PostId and v.UserId = c.UserId and v.VoteTypeId in (2,3)
    group by c.UserId
),
DuplicateQuestions as (
    select distinct pl.PostId as DuplicateQuestionId, pl.RelatedPostId as OriginalQuestionId
    from PostLinks pl
    inner join Posts p on pl.PostId = p.Id and p.PostTypeId = 1
    inner join Posts rp on pl.RelatedPostId = rp.Id and rp.PostTypeId = 1
    where pl.LinkTypeId = 3
),
RecentActiveQuestions as (
    select p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentRank
    from Posts p 
    where p.PostTypeId = 1 and p.ClosedDate is null
),
UserRecentActivity as (
    select ua.UserId, ua.Reputation, ua.Views, 
        ua.QuestionsCount, ua.AvgQuestionScore, ua.TotalQuestionViews,
        ua.AnswersCount, ua.AvgAnswerScore, ua.MaxAnswerScore,
        ucb.BadgeName,
        coalesce(uac.CommentsCount, 0) as CommentsCount,
        coalesce(uac.CommentUpVotes, 0) as CommentUpVotes,
        coalesce(uac.CommentDownVotes, 0) as CommentDownVotes,
        dq.DuplicateQuestionId,
        rq.Id as RecentQuestionId,
        rq.Title as RecentQuestionTitle,
        rq.Score as RecentQuestionScore,
        rq.ViewCount as RecentQuestionViews,
        rq.Tags as RecentQuestionTags
    from UserActivity ua
    left join TopUserBadges ucb on ua.UserId = ucb.UserId
    left join UserCommentsWithReactions uac on ua.UserId = uac.UserId
    left join (
        select distinct dq.DuplicateQuestionId, dq.OriginalQuestionId
        from DuplicateQuestions dq
        join Posts p on p.Id = dq.DuplicateQuestionId
        where p.PostTypeId = 1
    ) dq on dq.DuplicateQuestionId in (
        select Id from Posts where OwnerUserId = ua.UserId and PostTypeId = 1
    )
    left join RecentActiveQuestions rq on rq.OwnerUserId = ua.UserId and rq.RecentRank = 1
)
select 
    ura.UserId,
    ura.Reputation,
    ura.Views,
    ura.QuestionsCount,
    round(ura.AvgQuestionScore, 2) as AvgQuestionScore,
    ura.TotalQuestionViews,
    ura.AnswersCount,
    round(ura.AvgAnswerScore, 2) as AvgAnswerScore,
    ura.MaxAnswerScore,
    ura.BadgeName,
    ura.CommentsCount,
    ura.CommentUpVotes,
    ura.CommentDownVotes,
    ura.DuplicateQuestionId,
    ura.RecentQuestionId,
    ura.RecentQuestionTitle,
    ura.RecentQuestionScore,
    ura.RecentQuestionViews,
    (1.0 * ura.Reputation / nullif(ura.Views,0)) * 
        (1 / (1 + exp(-coalesce(CAST(ura.CommentsCount AS NUMERIC),0)/10))) as ReputationViewImpactScore,
    coalesce(
        nullif(
            split_part(
                substr(ura.RecentQuestionTags, 2, length(ura.RecentQuestionTags)-2),
                '><',
                1
            ), 
        ''),
        'no-tag') as RecentQuestionTopTag
from UserRecentActivity ura
where ura.Reputation > 5000
group by
    ura.UserId,
    ura.Reputation,
    ura.Views,
    ura.QuestionsCount,
    ura.AvgQuestionScore,
    ura.TotalQuestionViews,
    ura.AnswersCount,
    ura.AvgAnswerScore,
    ura.MaxAnswerScore,
    ura.BadgeName,
    ura.CommentsCount,
    ura.CommentUpVotes,
    ura.CommentDownVotes,
    ura.DuplicateQuestionId,
    ura.RecentQuestionId,
    ura.RecentQuestionTitle,
    ura.RecentQuestionScore,
    ura.RecentQuestionViews,
    ura.RecentQuestionTags
order by ReputationViewImpactScore desc, ura.Reputation desc
limit 50;