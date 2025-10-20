with recursive RecursiveTaggedPosts as (
    select p.Id, p.Title, p.Tags,
           array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) as TagCount,
           1 as Level
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null

    union all

    select p2.Id, p2.Title, p2.Tags,
           array_length(string_to_array(substring(p2.Tags, 2, length(p2.Tags)-2), '><'), 1) as TagCount,
           r.Level + 1
    from Posts p2
    join RecursiveTaggedPosts r on p2.ParentId = r.Id
    where p2.PostTypeId = 2 and p2.Tags is not null
),
UserBadgeStats as (
    select u.Id as UserId,
           u.DisplayName,
           count(distinct b.Id) as TotalBadges,
           count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
           count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
           count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
           max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostWithVotesAndComments as (
    select p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.Title,
           coalesce(v.UpVotes, 0) as UpVotes,
           coalesce(v.DownVotes, 0) as DownVotes,
           coalesce(c.CommentCount, 0) as CommentCount
    from Posts p
    left join (
        select PostId,
               sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
               sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by PostId
    ) v on v.PostId = p.Id
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
),
RankedAnswers as (
    select p.Id, p.ParentId, p.Score, p.CreationDate,
           row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2
),
ClosedQuestions as (
    select ph.PostId, ph.CreationDate as CloseDate, crt.Name as CloseReason
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
),
QuestionsWithCloseInfo as (
    select p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, cq.CloseDate, cq.CloseReason, p.OwnerUserId, p.AcceptedAnswerId
    from Posts p
    left join ClosedQuestions cq on cq.PostId = p.Id
    where p.PostTypeId = 1
),
ComplexUserActivity as (
    select u.Id as UserId, u.DisplayName,
           count(distinct p.Id) as TotalPosts,
           sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsPosted,
           sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersPosted,
           coalesce(sum(v.UpVotes), 0) as TotalUpVotesReceived,
           coalesce(sum(v.DownVotes), 0) as TotalDownVotesReceived,
           max(p.CreationDate) as LastPostDate,
           bool_or(p.ClosedDate is not null) as HasClosedPosts
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select p.OwnerUserId,
               sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
               sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        group by p.OwnerUserId
    ) v on v.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
)
select q.Id as QuestionId,
       q.Title,
       q.CreationDate as QuestionCreationDate,
       q.Score as QuestionScore,
       q.ViewCount as QuestionViews,
       q.Tags,
       q.CloseDate,
       q.CloseReason,
       a.Id as TopAnswerId,
       a.Score as TopAnswerScore,
       a.CreationDate as TopAnswerCreationDate,
       u.DisplayName as QuestionOwner,
       ub.TotalBadges,
       ub.GoldBadges,
       ub.SilverBadges,
       ub.BronzeBadges,
       ua.TotalPosts as OwnerTotalPosts,
       ua.QuestionsPosted as OwnerQuestions,
       ua.AnswersPosted as OwnerAnswers,
       ua.TotalUpVotesReceived as OwnerUpVotes,
       ua.TotalDownVotesReceived as OwnerDownVotes,
       ua.HasClosedPosts as OwnerHasClosedPosts,
       (select count(distinct pl.RelatedPostId)
        from PostLinks pl
        where pl.PostId = q.Id and pl.LinkTypeId = 1) as LinkedPostsCount,
       (select count(*)
        from Comments c
        where c.PostId = q.Id and c.Score > 0) as PositiveCommentsCount,
       (select string_agg(distinct lt.Name, ', ')
        from PostLinks pl2
        join LinkTypes lt on lt.Id = pl2.LinkTypeId
        where pl2.PostId = q.Id) as LinkTypesInvolved,
       dense_rank() over (order by q.Score desc) as QuestionScoreRank,
       avg(a.Score) over (partition by q.Tags) as AvgAnswerScoreByTag,
       row_number() over (partition by q.OwnerUserId order by q.CreationDate desc) as OwnerRecentQuestionRank
from QuestionsWithCloseInfo q
left join Posts a on a.Id = q.AcceptedAnswerId
left join Users u on u.Id = q.OwnerUserId
left join UserBadgeStats ub on ub.UserId = u.Id
left join ComplexUserActivity ua on ua.UserId = u.Id
where q.Score > 10
  and (q.CloseDate is null or q.CloseDate > q.CreationDate)
  and exists (
    select 1 from Posts a2
    where a2.ParentId = q.Id and a2.Score > 5
  )
order by q.Score desc, q.ViewCount desc
limit 100;