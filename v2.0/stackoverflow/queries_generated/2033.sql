-- {"query": "2033.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1296} 
with RecursiveVotes as (
    select v.Id, v.PostId, v.VoteTypeId, v.UserId, v.CreationDate, v.BountyAmount,
        row_number() over (partition by v.PostId order by v.CreationDate) as VoteOrder
    from Votes v
    where v.VoteTypeId in (2,3)
),
UserActivity as (
    select u.Id as UserId, u.DisplayName, u.Reputation, u.CreationDate, u.Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
        coalesce(sum(b.Class),0) as BadgeScore,
        min(ph.CreationDate) as FirstEditDate,
        max(ph.CreationDate) as LastEditDate,
        max(u.LastAccessDate) as LastAccess
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
QuestionScores as (
    select p.Id, p.OwnerUserId, p.CreationDate, p.Title, p.Score, p.ViewCount,
        string_agg(distinct substring(t.TagName from 1 for 20), ',') as TagsSummary
    from Posts p
    left join LATERAL (
        select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2),'><')) as TagName
    ) t on true
    where p.PostTypeId = 1
    group by p.Id, p.OwnerUserId, p.CreationDate, p.Title, p.Score, p.ViewCount
),
AnswerRankings as (
    select a.Id as AnswerId, a.ParentId as QuestionId, a.OwnerUserId as AnswererUserId,
        a.CreationDate, a.Score,
        rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as ScoreRank,
        count(*) over (partition by a.ParentId) as TotalAnswers
    from Posts a
    where a.PostTypeId = 2
),
TopAnswers as (
    select ar.*
    from AnswerRankings ar
    where ar.ScoreRank <= 3
),
DuplicatesCTE as (
    select pl.PostId, pl.RelatedPostId, pl.LinkTypeId, pt1.Title as PostTitle, pt2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts pt1 on pt1.Id = pl.PostId
    join Posts pt2 on pt2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
UserCommentsAgg as (
    select c.UserId, count(c.Id) as CommentCount,
        count(distinct c.PostId) as DistinctPostsCommented,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct substring(c.Text from 1 for 30), ' | ') as CommentsSample
    from Comments c
    group by c.UserId
),
FinalAggregation as (
    select ua.UserId, ua.DisplayName, ua.Reputation, ua.Location, ua.QuestionCount, ua.AnswerCount, ua.TotalPostScore, ua.BadgeScore,
        ua.FirstEditDate, ua.LastEditDate, ua.LastAccess,
        coalesce(uc.CommentCount,0) as TotalComments, coalesce(uc.DistinctPostsCommented,0) as PostsCommented,
        coalesce(uc.CommentsSample,'') as CommentsSample,
        (select count(*) from Posts p where p.PostTypeId=1 and p.OwnerUserId = ua.UserId and 
            p.CreationDate >= (ua.CreationDate + interval '1 year')
            and p.Score > 10) as HighScoreQuestionsAfterYear,
        (select avg(a.Score) from Posts a where a.PostTypeId=2 and a.OwnerUserId=ua.UserId) as AvgAnswerScore,
        (select count(distinct ph.PostId) from PostHistory ph where ph.UserId = ua.UserId and ph.PostHistoryTypeId in (4,5,6)) as EditsMade,
        (select count(*) from Votes v where v.UserId = ua.UserId and v.VoteTypeId=2) as UpVotesCast,
        (select count(*) from Votes v where v.UserId = ua.UserId and v.VoteTypeId=3) as DownVotesCast
    from UserActivity ua
    left join UserCommentsAgg uc on uc.UserId = ua.UserId
)
select fa.UserId, fa.DisplayName, fa.Reputation, fa.Location,
    fa.QuestionCount, fa.AnswerCount, fa.TotalPostScore, fa.BadgeScore,
    fa.FirstEditDate, fa.LastEditDate, fa.LastAccess,
    fa.TotalComments, fa.PostsCommented,
    fa.HighScoreQuestionsAfterYear, fa.AvgAnswerScore, fa.EditsMade, fa.UpVotesCast, fa.DownVotesCast,
    qs.Id as SampleQuestionId, qs.Title as SampleQuestionTitle,
    ta.AnswerId as TopAnswerId, ta.Score as TopAnswerScore,
    dup.PostId as DuplicateOfPostId, dup.RelatedPostId as OriginalPostId,
    dup.PostTitle as DuplicateTitle, dup.RelatedPostTitle as OriginalTitle
from FinalAggregation fa
left join QuestionScores qs on qs.OwnerUserId = fa.UserId
left join TopAnswers ta on ta.AnswererUserId = fa.UserId
left join DuplicatesCTE dup on dup.PostId = qs.Id
where fa.Reputation > 1000 and fa.QuestionCount > 5 and fa.TotalComments > 10
order by fa.Reputation desc, fa.TotalPostScore desc, fa.BadgeScore desc
limit 100;