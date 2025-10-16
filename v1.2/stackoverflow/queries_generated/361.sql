-- {"query": "361.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1568} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) as BadgeCount,
        sum(v.VoteCount) as TotalVotesReceived,
        row_number() over (partition by u.Location order by u.Reputation desc) as LocationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId in (2,3) -- UpMod and DownMod
        group by PostId
    ) v on v.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
TopUsers as (
    select UserId, DisplayName, Reputation, Location, QuestionCount, AnswerCount, CommentCount, BadgeCount, TotalVotesReceived, LocationRank
    from RecursiveUserActivity
    where LocationRank <= 5
),
PostStats as (
    select
        p.Id as PostId,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.Title,
        p.Tags,
        coalesce(p.AnswerCount,0) as AnswerCount,
        p.AcceptedAnswerId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as UserPostRank
    from Posts p
    left join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2)
),
AcceptedAnswerDetails as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerName
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
QuestionWithAcceptedAnswer as (
    select
        q.PostId as QuestionId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount,
        q.OwnerUserId,
        q.OwnerName,
        q.AnswerCount,
        a.AnswerId,
        a.AnswerScore,
        a.AnswerCreationDate,
        a.AnswerOwnerUserId,
        a.AnswerOwnerName,
        (a.AnswerCreationDate - q.CreationDate) as TimeToAcceptAnswer
    from PostStats q
    left join AcceptedAnswerDetails a on a.AnswerId = q.AcceptedAnswerId
    where q.PostTypeId = 1
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges,
        bool_or(b.TagBased) as HasTagBasedBadges
    from Badges b
    group by b.UserId
),
UserEngagement as (
    select
        u.Id as UserId,
        coalesce(ps.QuestionCount,0) as QuestionsPosted,
        coalesce(ps.AnswerCount,0) as AnswersPosted,
        coalesce(cmt.CommentCount,0) as CommentsMade,
        coalesce(vt.VotesCast,0) as VotesCast,
        coalesce(vr.VotesReceived,0) as VotesReceived
    from Users u
    left join (
        select OwnerUserId,
            count(*) filter (where PostTypeId = 1) as QuestionCount,
            count(*) filter (where PostTypeId = 2) as AnswerCount
        from Posts
        group by OwnerUserId
    ) ps on ps.OwnerUserId = u.Id
    left join (
        select UserId, count(*) as CommentCount
        from Comments
        group by UserId
    ) cmt on cmt.UserId = u.Id
    left join (
        select UserId, count(*) as VotesCast
        from Votes
        group by UserId
    ) vt on vt.UserId = u.Id
    left join (
        select p.OwnerUserId, count(v.Id) as VotesReceived
        from Votes v
        join Posts p on p.Id = v.PostId
        group by p.OwnerUserId
    ) vr on vr.OwnerUserId = u.Id
),
TopEngagedUsers as (
    select
        ue.UserId,
        u.DisplayName,
        ue.QuestionsPosted,
        ue.AnswersPosted,
        ue.CommentsMade,
        ue.VotesCast,
        ue.VotesReceived,
        (ue.QuestionsPosted + ue.AnswersPosted + ue.CommentsMade + ue.VotesCast + ue.VotesReceived) as TotalEngagementScore,
        row_number() over (order by (ue.QuestionsPosted + ue.AnswersPosted + ue.CommentsMade + ue.VotesCast + ue.VotesReceived) desc) as EngagementRank
    from UserEngagement ue
    join Users u on u.Id = ue.UserId
    where u.Reputation > 1000
)
select
    tu.DisplayName as TopUser,
    tu.Location,
    tu.Reputation,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.CommentCount,
    tu.BadgeCount,
    tu.TotalVotesReceived,
    qwa.QuestionId,
    qwa.Title as QuestionTitle,
    qwa.Tags,
    qwa.QuestionScore,
    qwa.ViewCount,
    qwa.AnswerCount as NumberOfAnswers,
    qwa.AnswerId as AcceptedAnswerId,
    qwa.AnswerScore,
    qwa.AnswerCreationDate,
    qwa.AnswerOwnerName,
    qwa.TimeToAcceptAnswer,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TotalBadges,
    ubs.HasTagBasedBadges,
    teu.QuestionsPosted,
    teu.AnswersPosted,
    teu.CommentsMade,
    teu.VotesCast,
    teu.VotesReceived,
    teu.TotalEngagementScore
from TopUsers tu
left join QuestionWithAcceptedAnswer qwa on qwa.OwnerUserId = tu.UserId
left join UserBadgeSummary ubs on ubs.UserId = tu.UserId
left join TopEngagedUsers teu on teu.UserId = tu.UserId
where qwa.QuestionScore > 5 or qwa.AnswerScore > 5
order by tu.Location, tu.Reputation desc, qwa.QuestionScore desc nulls last
limit 100;