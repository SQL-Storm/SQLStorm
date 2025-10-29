-- {"query": "2278.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1566} 
with RecursiveTagStats as (
    select
        t.Id as TagId,
        t.TagName,
        coalesce(p.AnswerCount,0) as TotalAnswers,
        coalesce(p.FavoriteCount,0) as TotalFavorites,
        coalesce(u.Reputation,0) as OwnerReputation,
        row_number() over (partition by t.Id order by p.Score desc nulls last) as rn
    from Tags t
    left join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
    left join Users u on u.Id = p.OwnerUserId
    where t.IsModeratorOnly = 0
),
TopTagQuestions as (
    select 
        rts.TagId,
        rts.TagName,
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        ph.Comment as CloseReason,
        count(c.Id) as CommentCount,
        avg(vt.Score) as AvgVoteScore,
        max(ph.CreationDate) as LastClosedDate
    from RecursiveTagStats rts
    inner join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', rts.TagName, '>%')
    left join Users u on u.Id = p.OwnerUserId
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    left join (
        select ph1.PostId, ph1.Comment, ph1.CreationDate
        from PostHistory ph1
        where ph1.PostHistoryTypeId = 10 -- Post Closed
          and ph1.CreationDate = (
            select max(ph2.CreationDate)
            from PostHistory ph2
            where ph2.PostId = ph1.PostId and ph2.PostHistoryTypeId = 10
          )
    ) ph on ph.PostId = p.Id
    group by rts.TagId, rts.TagName, p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.AcceptedAnswerId, u.DisplayName, u.Reputation, ph.Comment
    having count(c.Id) > 5 and avg(vt.Score) > 1.5
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as AcceptedAnswerExists
    from Posts a
    inner join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionWithStats as (
    select
        tq.TagId,
        tq.TagName,
        tq.QuestionId,
        tq.Title,
        tq.CreationDate,
        tq.Score,
        tq.ViewCount,
        tq.AnswerCount as QuestionAnswerCount,
        tq.FavoriteCount,
        tq.AcceptedAnswerId,
        tq.OwnerDisplayName,
        tq.OwnerReputation,
        tq.CloseReason,
        tq.CommentCount,
        tq.AvgVoteScore,
        tq.LastClosedDate,
        coalesce(a.AnswerCount,0) as AnswerCount,
        coalesce(a.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(a.MaxAnswerScore,0) as MaxAnswerScore,
        coalesce(a.AcceptedAnswerExists,0) as AcceptedAnswerExists
    from TopTagQuestions tq
    left join AnswerStats a on a.QuestionId = tq.QuestionId
),
BadgesCounts as (
    select UserId, count(*) filter(where Class = 1) as GoldBadges,
        count(*) filter(where Class = 2) as SilverBadges,
        count(*) filter(where Class = 3) as BronzeBadges
    from Badges
    group by UserId
),
UserActivity as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        bc.GoldBadges,
        bc.SilverBadges,
        bc.BronzeBadges,
        max(p.CreationDate) as LastPostDate,
        count(p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCount,
        sum(v.VoteTypeId = 2)::int as TotalUpVotes,
        sum(v.VoteTypeId = 3)::int as TotalDownVotes
    from Users u
    left join BadgesCounts bc on bc.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges
),
RankedQuestions as (
    select
        *,
        rank() over (partition by TagName order by Score desc, AnswerCount desc) as RankByScore,
        dense_rank() over (order by CreationDate desc) as RecentRank
    from QuestionWithStats
),
CloseReasonLookup as (
    select Id, Name from CloseReasonTypes
),
DuplicateQuestionLinks as (
    select pl.PostId as DuplicateId, pl.RelatedPostId as OriginalId
    from PostLinks pl
    where pl.LinkTypeId = 3
)
select 
    rq.TagName,
    rq.Title as QuestionTitle,
    rq.Score as QuestionScore,
    rq.ViewCount,
    rq.AnswerCount as AnswerCount,
    rq.AvgAnswerScore,
    rq.MaxAnswerScore,
    rq.AcceptedAnswerExists,
    coalesce(crt.Name, rq.CloseReason) as CloseReason,
    rq.CommentCount,
    rq.AvgVoteScore,
    rq.LastClosedDate,
    ua.DisplayName as OwnerUser,
    ua.Reputation as OwnerReputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.TotalPosts,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    dup.OriginalId as DuplicateOfQuestionId,
    dupt.Title as OriginalQuestionTitle
from RankedQuestions rq
left join UserActivity ua on ua.DisplayName = rq.OwnerDisplayName
left join CloseReasonLookup crt on crt.Id = cast(rq.CloseReason as integer) and rq.CloseReason ~ '^\d+$'
left join DuplicateQuestionLinks dup on dup.DuplicateId = rq.QuestionId
left join Posts dupt on dupt.Id = dup.OriginalId
where (rq.RankByScore <= 10 or rq.RecentRank <= 20)
  and (rq.CloseReason is null or rq.CloseReason = '' or crt.Name is not null)
order by rq.TagName, rq.Score desc, rq.CreationDate desc
limit 100;