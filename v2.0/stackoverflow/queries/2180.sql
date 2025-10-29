with RecursiveUserReputation as (
    select u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location,
           row_number() over (order by u.Reputation desc, u.CreationDate asc) as Rank,
           coalesce(b.GoldBadges,0) as GoldBadges,
           coalesce(b.SilverBadges,0) as SilverBadges,
           coalesce(b.BronzeBadges,0) as BronzeBadges
    from Users u
    left join (
        select UserId,
               sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
               sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
               sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
        from Badges
        group by UserId
    ) b on b.UserId = u.Id
    where u.Reputation is not null
),
TopQuestionsWithAnswerStats as (
    select q.Id as QuestionId, q.Title, q.CreationDate, q.ViewCount, q.Score,
           q.OwnerUserId, u.DisplayName as OwnerDisplayName,
           count(a.Id) filter (where a.Score > 0) as PositiveAnswersCount,
           count(a.Id) as TotalAnswersCount,
           avg(a.Score) filter (where a.Id is not null) as AvgAnswerScore,
           max(a.Score) filter (where a.Id is not null) as MaxAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = q.OwnerUserId
    where q.PostTypeId = 1 and q.Score >= 10 and q.ViewCount >= 1000
    group by q.Id, q.Title, q.CreationDate, q.ViewCount, q.Score, q.OwnerUserId, u.DisplayName
),
RankedAnswersWithComments as (
    select a.Id as AnswerId, a.ParentId as QuestionId, a.OwnerUserId, a.Score, a.CreationDate,
           c.CommentCount, c.TopCommentText,
           row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    left join (
        select PostId,
               count(*) as CommentCount,
               substring(string_agg(Text, ' | ' order by Score desc, CreationDate asc), 1, 200) as TopCommentText
        from Comments
        group by PostId
    ) c on c.PostId = a.Id
    where a.PostTypeId = 2
),
AnswerVotesAgg as (
    select v.PostId,
           sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
           sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
           sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
CorrelatedLatestEdit as (
    select ph.PostId, ph.CreationDate as LastEditDate, ph.UserId as EditorUserId,
           ph.UserDisplayName as EditorDisplayName, ph.Comment as EditComment,
           row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
),
QuestionsWithLatestEdit as (
    select q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount,
           le.LastEditDate, le.EditorUserId, le.EditorDisplayName,
           le.EditComment
    from Posts q
    left join CorrelatedLatestEdit le on le.PostId = q.Id and le.rn = 1
    where q.PostTypeId = 1
),
QuestionDuplicates as (
    select pl.PostId as DuplicateQuestionId, pl.RelatedPostId as OriginalQuestionId,
           pl.CreationDate, u.DisplayName as DuplicateOwner,
           dup.Score as DuplicateScore, orig.Score as OriginalScore
    from PostLinks pl
    join Posts dup on dup.Id = pl.PostId and dup.PostTypeId = 1
    join Posts orig on orig.Id = pl.RelatedPostId and orig.PostTypeId = 1
    left join Users u on u.Id = dup.OwnerUserId
    where pl.LinkTypeId = 3
),
UnionAllVotesAndComments as (
    select v.UserId, count(*) as VoteCount, cast(null as int) as CommentCount
    from Votes v
    group by v.UserId
    union all
    select c.UserId, cast(null as int) as VoteCount, count(*) as CommentCount
    from Comments c
    group by c.UserId
),
UserVotesAndCommentsAgg as (
    select UserId,
           sum(coalesce(VoteCount,0)) as TotalVotes,
           sum(coalesce(CommentCount,0)) as TotalComments
    from UnionAllVotesAndComments
    group by UserId
),
UserActivityScore as (
    select u.Id, u.DisplayName,
           u.Reputation,
           coalesce(vac.TotalVotes,0) as VotesGiven,
           coalesce(vac.TotalComments,0) as CommentsMade,
           coalesce(badges.GoldBadges,0) as GoldBadges,
           coalesce(badges.SilverBadges,0) as SilverBadges,
           coalesce(badges.BronzeBadges,0) as BronzeBadges,
           (u.Reputation * 0.5 + coalesce(vac.TotalVotes,0) * 1.2 + coalesce(vac.TotalComments,0) * 1.0 +
            coalesce(badges.GoldBadges,0) * 20 + coalesce(badges.SilverBadges,0) * 10 + coalesce(badges.BronzeBadges,0) * 5) as ActivityScore
    from Users u
    left join UserVotesAndCommentsAgg vac on vac.UserId = u.Id
    left join (
        select UserId,
               sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
               sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
               sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
        from Badges
        group by UserId
    ) badges on badges.UserId = u.Id
),
FinalFilteredQuestions as (
    select q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.OwnerUserId,
           q.LastEditDate, q.EditorUserId, q.EditComment,
           coalesce(ts.PositiveAnswersCount,0) as PositiveAnswersCount,
           coalesce(ts.TotalAnswersCount,0) as TotalAnswersCount,
           coalesce(ts.AvgAnswerScore,0) as AvgAnswerScore,
           coalesce(ts.MaxAnswerScore,0) as MaxAnswerScore
    from QuestionsWithLatestEdit q
    left join TopQuestionsWithAnswerStats ts on ts.QuestionId = q.Id
    where q.Score > 20 and q.ViewCount > 5000
),
QuestionsWithDuplicatesInfo as (
    select f.Id, f.Title, f.CreationDate, f.Score, f.ViewCount, f.OwnerUserId,
           f.LastEditDate, f.EditorUserId, f.EditComment,
           f.PositiveAnswersCount, f.TotalAnswersCount, f.AvgAnswerScore, f.MaxAnswerScore,
           d.OriginalQuestionId, d.CreationDate as DuplicateDate, d.DuplicateOwner, d.DuplicateScore, d.OriginalScore
    from FinalFilteredQuestions f
    left join QuestionDuplicates d on d.DuplicateQuestionId = f.Id
    where d.DuplicateQuestionId is not null
),
WindowedQuestionRanks as (
    select Id, Title, CreationDate, Score, ViewCount, OwnerUserId,
           LastEditDate, EditorUserId, EditComment,
           PositiveAnswersCount, TotalAnswersCount, AvgAnswerScore, MaxAnswerScore,
           OriginalQuestionId, DuplicateDate, DuplicateOwner, DuplicateScore, OriginalScore,
           rank() over (partition by OriginalQuestionId order by DuplicateDate asc) as DuplicateRank,
           count(*) over (partition by OriginalQuestionId) as DuplicateCount
    from QuestionsWithDuplicatesInfo
)
select wq.Id as QuestionId,
       wq.Title,
       wq.CreationDate as QuestionCreationDate,
       wq.Score as QuestionScore,
       wq.ViewCount as QuestionViews,
       u.DisplayName as OwnerName,
       au.Reputation as OwnerReputation,
       wq.LastEditDate,
       wq.EditorUserId,
       wq.EditComment,
       wq.PositiveAnswersCount,
       wq.TotalAnswersCount,
       round(cast(wq.AvgAnswerScore as numeric),2) as AvgAnswerScore,
       wq.MaxAnswerScore,
       wq.OriginalQuestionId,
       orig.Title as OriginalQuestionTitle,
       wq.DuplicateDate,
       wq.DuplicateRank,
       wq.DuplicateCount,
       wq.DuplicateOwner,
       wq.DuplicateScore,
       wq.OriginalScore,
       ua.VotesGiven,
       ua.CommentsMade,
       ua.GoldBadges,
       ua.SilverBadges,
       ua.BronzeBadges,
       round(cast(ua.ActivityScore as numeric),2) as UserActivityScore
from WindowedQuestionRanks wq
join Posts q on q.Id = wq.Id
left join Posts orig on orig.Id = wq.OriginalQuestionId
left join Users u on u.Id = q.OwnerUserId
left join RecursiveUserReputation au on au.Id = q.OwnerUserId
left join UserActivityScore ua on ua.Id = q.OwnerUserId
where q.Title is not null
order by wq.DuplicateCount desc, wq.Score desc, wq.ViewCount desc
limit 100;