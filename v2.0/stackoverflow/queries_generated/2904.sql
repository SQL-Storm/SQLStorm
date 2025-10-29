-- {"query": "2904.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1269} 
with RecursiveUserBadges AS (
    select u.Id as UserId, u.DisplayName,
        b.Name as BadgeName, b.Class, b.Date,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    where b.Date >= date_trunc('year', current_date) - interval '2 years'
), LatestBadges AS (
    select UserId, BadgeName, Class, Date
    from RecursiveUserBadges
    where rn <= 3
), QuestionsWithAcceptedAnswers AS (
    select p.Id as QuestionId, p.Title, p.CreationDate, p.OwnerUserId,
        p.AcceptedAnswerId, a.Score as AcceptedAnswerScore,
        p.Score as QuestionScore, p.Tags
    from Posts p
    left join Posts a on a.Id = p.AcceptedAnswerId and a.PostTypeId = 2
    where p.PostTypeId = 1 and p.AcceptedAnswerId is not null
), UserActivityStats AS (
    select u.Id as UserId, u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        count(distinct c.Id) as CommentsCount,
        coalesce(sum(v.Amount), 0) as TotalBountyGiven
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select UserId, coalesce(sum(BountyAmount),0) as Amount
        from Votes
        where VoteTypeId = 8 -- BountyStart
        group by UserId
    ) v on v.UserId = u.Id
    group by u.Id, u.DisplayName
), TagQuestionRanks AS (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag,
        p.Score,
        rank() over (partition by unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) order by p.Score desc) as TagScoreRank
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null and p.Tags <> ''
), TagTopQuestions AS (
    select PostId, Tag
    from TagQuestionRanks
    where TagScoreRank <= 5
), UserLinkedPosts AS (
    select ulp.UserId, count(distinct pl.PostId) as LinkedPostCount
    from (
        select distinct OwnerUserId as UserId, Id as PostId
        from Posts where OwnerUserId is not null
    ) ulp
    left join PostLinks pl on pl.PostId = ulp.PostId and pl.LinkTypeId = 1 -- Linked
    group by ulp.UserId
), ComplexStringAnalysis AS (
    select p.Id as PostId,
        length(p.Body) - length(replace(p.Body, 'SQL', '')) as SQLOccurrences,
        case when p.Tags like '%<sql>%' then 1 else 0 end as HasSQLTag,
        left(p.Title, 40) as TitleSnippet
    from Posts p
    where p.PostTypeId = 1
), CorrelatedSubqueryInfo AS (
    select p.Id as PostId, p.OwnerUserId,
        (select count(*)
         from Comments c
         where c.PostId = p.Id and c.CreationDate > p.CreationDate) as NewerCommentsCount,
        (select max(Score)
         from Votes v
         where v.PostId = p.Id and v.VoteTypeId = 2) as MaxUpVotes
    from Posts p
    where p.PostTypeId = 2
)
select
    u.Id as UserId,
    u.DisplayName,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.CommentsCount,
    ua.TotalBountyGiven,
    coalesce(ul.LinkedPostCount,0) as LinkedPosts,
    lb.BadgeName,
    lb.Class as BadgeClass,
    q.Title as RecentTopQuestion,
    q.AcceptedAnswerScore,
    csa.SQLOccurrences,
    csa.HasSQLTag,
    csa.TitleSnippet,
    coalesce(cs.NewerCommentsCount,0) as NewerCommentsOnAnswer,
    coalesce(cs.MaxUpVotes,0) as MaxUpVotesOnAnswer,
    ts.Tag,
    ts.PostId as TopQuestionId,
    ts.TagScoreRank
from Users u
left join UserActivityStats ua on ua.UserId = u.Id
left join LatestBadges lb on lb.UserId = u.Id
left join Lateral (
    select q1.Title, q1.AcceptedAnswerScore
    from QuestionsWithAcceptedAnswers q1
    where q1.OwnerUserId = u.Id
    order by q1.CreationDate desc
    limit 1
) q on true
left join ComplexStringAnalysis csa on csa.PostId = q.TopQuestionId
left join UserLinkedPosts ul on ul.UserId = u.Id
left join CorrelatedSubqueryInfo cs on cs.OwnerUserId = u.Id
left join TagTopQuestions ts on ts.Tag in (
    select distinct unnest(string_to_array(substring(t.Tags from 2 for char_length(t.Tags) - 2), '><'))
    from Posts t where t.OwnerUserId = u.Id and t.PostTypeId = 1
)
where ua.QuestionsCount > 10
and (lb.Class is null or lb.Class <= 2)
and (
    csa.SQLOccurrences > 0 or csa.HasSQLTag = 1 or ua.TotalBountyGiven > 1000
)
order by ua.TotalBountyGiven desc, ua.AnswersCount desc
limit 50;