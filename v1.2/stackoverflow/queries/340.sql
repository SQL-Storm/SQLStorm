with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        sum(v.VoteCount) as TotalVotesReceived,
        sum(case when v.VoteTypeId = 2 then v.VoteCount else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then v.VoteCount else 0 end) as DownVotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, VoteTypeId, count(*) as VoteCount
        from Votes
        group by PostId, VoteTypeId
    ) v on v.PostId = p.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopTags as (
    select
        t.TagName,
        t.Count,
        t.Id,
        p.OwnerUserId,
        count(p.Id) as PostsWithTag
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
    group by t.TagName, t.Count, t.Id, p.OwnerUserId
    order by PostsWithTag desc
    limit 100
),
UserBadgesRanked as (
    select
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        row_number() over (partition by b.UserId order by b.Class, b.Date desc) as BadgeRank
    from Badges b
),
UserTopBadges as (
    select
        UserId,
        array_agg(Name order by Class, Date desc) filter (where BadgeRank <= 3) as TopBadges
    from UserBadgesRanked
    group by UserId
),
PostLinkDetails as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Score as PostScore,
        p2.Score as RelatedPostScore,
        p1.CreationDate as PostCreationDate,
        p2.CreationDate as RelatedPostCreationDate
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
TopAnswersPerQuestion as (
    select
        QuestionId,
        Title,
        OwnerUserId,
        QuestionScore,
        ViewCount,
        AnswerCount,
        AnswerId,
        AnswerScore,
        AnswerCreationDate
    from QuestionAnswerStats
    where AnswerRank = 1
),
UserActivityWithBadges as (
    select
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.CreationDate,
        rua.LastAccessDate,
        rua.QuestionCount,
        rua.AnswerCount,
        rua.CommentCount,
        rua.TotalVotesReceived,
        rua.UpVotesReceived,
        rua.DownVotesReceived,
        utb.TopBadges
    from RecursiveUserActivity rua
    left join UserTopBadges utb on utb.UserId = rua.UserId
),
QuestionsWithCloseInfo as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.ClosedDate,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where p.PostTypeId = 1
),
DuplicateQuestions as (
    select distinct
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        p1.Title as DuplicateTitle,
        p2.Title as OriginalTitle,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where pl.LinkTypeId = 3
),
UserReputationWindow as (
    select
        Id as UserId,
        Reputation,
        CreationDate,
        row_number() over (order by Reputation desc, Id) as RankByReputation,
        rank() over (partition by date_trunc('year', CreationDate) order by Reputation desc) as YearlyRank
    from Users
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.CreationDate,
    ua.LastAccessDate,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.TotalVotesReceived,
    ua.UpVotesReceived,
    ua.DownVotesReceived,
    coalesce(array_to_string(ua.TopBadges, ', '), 'No badges') as TopBadges,
    tq.Title as TopQuestionTitle,
    tq.Score as TopQuestionScore,
    tq.ViewCount as TopQuestionViews,
    tq.AnswerCount as TopQuestionAnswers,
    ta.AnswerId as TopAnswerId,
    ta.AnswerScore as TopAnswerScore,
    dq.DuplicateQuestionId,
    dq.OriginalQuestionId,
    dq.DuplicateTitle,
    dq.OriginalTitle,
    dq.LinkCreationDate,
    qci.ClosedDate,
    qci.CloseReasonName,
    urw.RankByReputation,
    urw.YearlyRank
from UserActivityWithBadges ua
left join (
    select OwnerUserId, max(Score) as MaxScore
    from Posts
    where PostTypeId = 1
    group by OwnerUserId
) maxq on maxq.OwnerUserId = ua.UserId
left join Posts tq on tq.OwnerUserId = ua.UserId and tq.PostTypeId = 1 and tq.Score = maxq.MaxScore
left join TopAnswersPerQuestion ta on ta.OwnerUserId = ua.UserId and ta.QuestionId = tq.Id
left join DuplicateQuestions dq on dq.DuplicateQuestionId = tq.Id
left join QuestionsWithCloseInfo qci on qci.Id = tq.Id
left join UserReputationWindow urw on urw.UserId = ua.UserId
where ua.Reputation > 1000
order by ua.Reputation desc, ua.UserId
limit 100;