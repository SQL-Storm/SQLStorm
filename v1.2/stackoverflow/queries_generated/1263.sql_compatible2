with RecursiveClosedQuestions as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        ph.CreationDate as CloseDate,
        ph.UserId as CloserUserId,
        u.DisplayName as CloserUserName,
        ROW_NUMBER() over (partition by p.Id order by ph.CreationDate asc) as CloseRN
    from Posts p
    inner join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join Users u on u.Id = ph.UserId
    where p.PostTypeId = 1
),
LatestClose AS (
    select * from RecursiveClosedQuestions where CloseRN = 1
),
AnswersWithScores as (
    select
        a.Id,
        a.ParentId,
        a.Score,
        a.OwnerUserId,
        u.Reputation,
        u.DisplayName,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    left join Users u on a.OwnerUserId = u.Id
    left join (
        select 
            PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        inner join VoteTypes vt on v.VoteTypeId = vt.Id
        group by PostId
    ) v on v.PostId = a.Id
    where a.PostTypeId = 2
),
CommentsByUser as (
    select
        c.UserId,
        p.PostTypeId,
        count(c.Id) as NumComments,
        count(distinct p.Id) as DistinctCommentedPosts
    from Comments c
    inner join Posts p on c.PostId = p.Id
    where c.UserId is not null
    group by c.UserId, p.PostTypeId
),
ActiveUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(bc.BadgeGold,0) as BadgeGold,
        coalesce(bc.BadgeSilver,0) as BadgeSilver,
        coalesce(bc.BadgeBronze,0) as BadgeBronze,
        coalesce(cu.QuestionsCommented,0) as QuestionsCommented,
        coalesce(cu.AnswersCommented,0) as AnswersCommented
    from Users u
    left join (
        select
            UserId,
            sum(case when Class = 1 then 1 else 0 end) as BadgeGold,
            sum(case when Class = 2 then 1 else 0 end) as BadgeSilver,
            sum(case when Class = 3 then 1 else 0 end) as BadgeBronze
        from Badges
        group by UserId
    ) bc on bc.UserId = u.Id
    left join (
        select
            UserId,
            sum(case when PostTypeId = 1 then NumComments else 0 end) as QuestionsCommented,
            sum(case when PostTypeId = 2 then NumComments else 0 end) as AnswersCommented
        from CommentsByUser
        group by UserId
    ) cu on cu.UserId = u.Id
    where u.Reputation > 1000
),
TopPostsWithLinksAndHistory as (
    select 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        array_agg(distinct lt.Name) filter (where lt.Name is not null) as LinkTypeNames,
        case when p.AcceptedAnswerId is null then 'No Accepted Answer' else 'Has Accepted Answer' end as AcceptedStatus,
        (select count(*) from PostHistory ph where ph.PostId = p.Id) as HistoryCount,
        (select count(*) from PostLinks pl where pl.PostId = p.Id) as LinkCount
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
    where p.PostTypeId = 1 and p.Score > 10 and p.CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - interval '365 day')
    group by p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, p.Tags, p.AcceptedAnswerId
),
UserReputationGrowth as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) as TotalQuestions,
        count(distinct a.Id) as TotalAnswers,
        sum(coalesce(p.Score,0)) as QuestionScoreSum,
        sum(coalesce(a.Score,0)) as AnswerScoreSum,
        (u.Reputation - created_sub.ReputationAtCreation) as ReputationGrowth,
        rank() over (order by (u.Reputation - created_sub.ReputationAtCreation) desc) as GrowthRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join (
        select 
            u.Id,
            u.CreationDate,
            u.Reputation as ReputationAtCreation
        from Users u
    ) created_sub on created_sub.Id = u.Id
    group by u.Id, u.DisplayName, u.Reputation, created_sub.ReputationAtCreation
)
select
    t.Title as QuestionTitle,
    t.Score as QuestionScore,
    t.ViewCount as QuestionViews,
    array_to_string(string_to_array(coalesce(t.Tags,''), '><'), ', ') as ParsedTags,
    t.AcceptedStatus,
    coalesce(aas.a1_DisplayName, 'No Top Answer') as TopAnswerOwner,
    aas.a1_Score as TopAnswerScore,
    aas.a1_Reputation as TopAnswerOwnerReputation,
    aas.a1_UpVotes as TopAnswerUpVotes,
    aas.a1_DownVotes as TopAnswerDownVotes,
    t.LinkCount,
    t.HistoryCount,
    c.CloseDate,
    c.CloserUserName,
    u.DisplayName as QuestionOwner,
    u.Reputation as QuestionOwnerReputation,
    coalesce(u_act.BadgeGold,0) as BadgeGold,
    coalesce(u_act.BadgeSilver,0) as BadgeSilver,
    coalesce(u_act.BadgeBronze,0) as BadgeBronze,
    coalesce(u_act.QuestionsCommented,0) as QuestionsCommented,
    coalesce(u_act.AnswersCommented,0) as AnswersCommented,
    urg.ReputationGrowth,
    urg.GrowthRank
from TopPostsWithLinksAndHistory t
left join AnswersWithScores a1 on a1.ParentId = t.Id and a1.AnswerRank = 1
left join Users u on u.Id = (select OwnerUserId from Posts where Id = t.Id)
left join LatestClose c on c.Id = t.Id
left join ActiveUsers u_act on u_act.Id = u.Id
left join UserReputationGrowth urg on urg.Id = u.Id
left join LATERAL (
    select 
        a1.DisplayName as a1_DisplayName,
        a1.Score as a1_Score,
        a1.Reputation as a1_Reputation,
        a1.UpVotes as a1_UpVotes,
        a1.DownVotes as a1_DownVotes
) aas on true
group by
    t.Title,
    t.Score,
    t.ViewCount,
    t.Tags,
    t.AcceptedStatus,
    aas.a1_DisplayName,
    aas.a1_Score,
    aas.a1_Reputation,
    aas.a1_UpVotes,
    aas.a1_DownVotes,
    t.LinkCount,
    t.HistoryCount,
    c.CloseDate,
    c.CloserUserName,
    u.DisplayName,
    u.Reputation,
    u_act.BadgeGold,
    u_act.BadgeSilver,
    u_act.BadgeBronze,
    u_act.QuestionsCommented,
    u_act.AnswersCommented,
    urg.ReputationGrowth,
    urg.GrowthRank,
    t.Id,
    t.CreationDate
order by t.Score desc, t.ViewCount desc
limit 50;