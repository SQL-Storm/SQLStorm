-- {"query": "2241.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1262}
with RankedUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    where b.Class in (1, 2, 3)
),
TopBadgesPerUser as (
    select UserId, DisplayName, BadgeName, Class
    from RankedUserBadges
    where rn = 1
),
QuestionStats as (
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        coalesce(p.Score, 0) as Score,
        coalesce(p.ViewCount, 0) as Views,
        coalesce(p.AnswerCount, 0) as Answers,
        p.Tags,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentsCount,
        (select count(v.Id) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(v.Id) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes
    from Posts p
    where p.PostTypeId = 1
),
AnswerScores as (
    select
        p.ParentId as QuestionId,
        avg(abs(cast(p.Score as numeric))) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        count(*) as AnswerCount
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as UserQuestions,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as UserAnswers,
        sum(coalesce(p.Score,0)) as TotalPostScore,
        sum(coalesce(vp.UpVotes, 0)) as UserUpVotes,
        sum(coalesce(vp.DownVotes, 0)) as UserDownVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            PostId,
            count(case when VoteTypeId = 2 then 1 end) as UpVotes,
            count(case when VoteTypeId = 3 then 1 end) as DownVotes
        from Votes
        group by PostId
    ) vp on vp.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedTitle,
        pl.CreationDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name = 'Duplicate'
),
PostsWithCloseReason as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
),
QuestionWithDetails as (
    select
        q.QuestionId,
        q.OwnerUserId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.Views,
        q.Answers,
        q.Tags,
        q.CommentsCount,
        q.UpVotes,
        q.DownVotes,
        au.DisplayName as OwnerName,
        au.Reputation as OwnerReputation,
        tb.BadgeName as TopBadge,
        tb.Class as TopBadgeClass,
        coalesce(ans.AvgAnswerScore, 0) as AverageAnswerScore,
        coalesce(ans.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(ans.AnswerCount, 0) as NumberOfAnswers,
        cl.CloseReason,
        cl.CloseDate,
        dl.RelatedPostId as DuplicateOf,
        dl.RelatedTitle as DuplicateOfTitle
    from QuestionStats q
    left join Users au on au.Id = q.OwnerUserId
    left join TopBadgesPerUser tb on tb.UserId = q.OwnerUserId
    left join AnswerScores ans on ans.QuestionId = q.QuestionId
    left join PostsWithCloseReason cl on cl.PostId = q.QuestionId
    left join DuplicateLinks dl on dl.PostId = q.QuestionId
),
RankedQuestionsByScore as (
    select
        q.QuestionId,
        q.OwnerUserId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.Views,
        q.Answers,
        q.Tags,
        q.CommentsCount,
        q.UpVotes,
        q.DownVotes,
        q.OwnerName,
        q.OwnerReputation,
        q.TopBadge,
        q.TopBadgeClass,
        q.AverageAnswerScore,
        q.MaxAnswerScore,
        q.NumberOfAnswers,
        q.CloseReason,
        q.CloseDate,
        q.DuplicateOf,
        q.DuplicateOfTitle,
        rank() over (order by q.Score desc, q.Views desc) as ScoreRank,
        row_number() over (partition by q.CloseReason order by q.CreationDate desc) as RecentClosedRank
    from QuestionWithDetails q
)
select
    rq.ScoreRank,
    rq.QuestionId,
    rq.Title,
    substring(rq.Tags from 2 for char_length(rq.Tags) - 2) as TrimmedTags,
    rq.Score,
    rq.Views,
    rq.NumberOfAnswers,
    rq.AverageAnswerScore,
    rq.MaxAnswerScore,
    rq.CommentsCount,
    rq.UpVotes,
    rq.DownVotes,
    rq.OwnerUserId,
    rq.OwnerName,
    rq.OwnerReputation,
    rq.TopBadge,
    case when rq.TopBadgeClass = 1 then 'Gold'
         when rq.TopBadgeClass = 2 then 'Silver'
         when rq.TopBadgeClass = 3 then 'Bronze'
         else 'None' end as BadgeClass,
    rq.CloseReason,
    rq.CloseDate,
    rq.DuplicateOf,
    rq.DuplicateOfTitle,
    rq.RecentClosedRank
from RankedQuestionsByScore rq
where rq.ScoreRank <= 100
order by rq.ScoreRank;