-- {"query": "2038.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1301} 
with UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(u.Reputation,0) as Reputation,
        coalesce(u.UpVotes,0) as UpVotes,
        coalesce(u.DownVotes,0) as DownVotes,
        case when u.DownVotes = 0 then null else cast(u.UpVotes as float)/u.DownVotes end as UpDownRatio,
        u.CreationDate,
        row_number() over (order by coalesce(u.Reputation,0) desc, u.Id) as RankByRep
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.CreationDate
),
TopQuestions as (
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate asc) as RN
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (current_date - interval '365 days')
),
TopAnswersWithQuestion as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        q.Title as QuestionTitle,
        q.Score as QuestionScore,
        q.Tags as QuestionTags
    from Posts a
    inner join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    where a.PostTypeId = 2
      and a.Score >= 10
),
LatestCommentPerPost as (
    select distinct on (PostId)
        c.PostId,
        c.Id as CommentId,
        c.UserId as CommentUserId,
        c.CreationDate as CommentCreationDate,
        c.Text as CommentText
    from Comments c
    order by c.PostId, c.CreationDate desc
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
UserActivitySummary as (
    select
        u.Id as UserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id
)
select 
    ubs.DisplayName,
    ubs.Reputation,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.UpVotes,
    ubs.DownVotes,
    coalesce(ubs.UpDownRatio, 0) as UpDownRatio,
    tas.QuestionId,
    tas.Title as TopQuestionTitle,
    tas.Score as TopQuestionScore,
    tas.ViewCount as TopQuestionViews,
    tas.AnswerCount as TopQuestionAnswerCount,
    tas.FavoriteCount as TopQuestionFavorites,
    tas.ClosedDate as TopQuestionClosedDate,
    tas.Tags as TopQuestionTags,
    awa.AnswerId,
    awa.AnswerScore,
    awa.QuestionTitle as AnsweredQuestionTitle,
    awa.QuestionScore as AnsweredQuestionScore,
    awa.QuestionTags as AnsweredQuestionTags,
    lcp.CommentId,
    substr(lcp.CommentText, 1, 50) || 
      case when length(lcp.CommentText) > 50 then '...' else '' end as LatestCommentSnippet,
    dupl.RelatedPostId as DuplicateOfPostId,
    dupl.RelatedPostTitle as DuplicateOfPostTitle,
    uas.QuestionsAsked,
    uas.AnswersGiven,
    uas.CommentsMade,
    uas.UpVotesGiven,
    uas.DownVotesGiven,
    uas.LastPostDate,
    uas.LastCommentDate,
    dense_rank() over (order by ubs.Reputation desc, ubs.GoldBadges desc, ubs.SilverBadges desc) as GlobalUserRank
from UserBadgeStats ubs
left join TopQuestions tas on tas.OwnerUserId = ubs.UserId and tas.RN = 1
left join TopAnswersWithQuestion awa on awa.AnswerOwnerUserId = ubs.UserId
left join LatestCommentPerPost lcp on lcp.PostId = tas.QuestionId
left join DuplicateLinks dupl on dupl.PostId = tas.QuestionId
left join UserActivitySummary uas on uas.UserId = ubs.UserId
where ubs.Reputation > 1000
  and tas.Score > 5
  and (awa.AnswerScore > tas.Score / 2 or awa.AnswerScore is null)
order by ubs.Reputation desc, tas.Score desc
limit 100;