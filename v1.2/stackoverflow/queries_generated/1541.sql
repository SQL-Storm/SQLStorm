-- {"query": "1541.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1670} 
with RecursiveTagCounts AS (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        case when t.IsModeratorOnly = 1 then 'YES' else 'NO' end as ModeratorOnly,
        Dense_Rank() over (order by t.Count desc, t.TagName) as TagRank,
        array[ t.Id ] as Ancestors
    from Tags t
    where t Is not null
    union all
    select
        r.TagId,
        r.TagName,
        r.Count,
        r.ModeratorOnly,
        r.TagRank,
        r.Ancestors || r.TagId
    from RecursiveTagCounts r
    where cardinality(r.Ancestors) < 5
),
RecentHighScoringAnswers AS (
    select
        a.Id,
        a.ParentId,
        a.OwnerUserId,
        a.CreationDate,
        p.Score,
        row_number() over (partition by a.ParentId order by p.Score desc, a.CreationDate desc) as AnswerRank
    from Posts a
    inner join Posts p on p.Id = a.Id
    where a.PostTypeId = 2 -- answers
      and a.CreationDate >= now() - interval '6 months'
      and p.Score >= 10
),
UserAggregate AS (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) as BadgeCount,
        max(b.Class) filter (where b.Name ilike '%gold%') as HighestBadgeClass,
        avg(coalesce(v.Count, 0)) as AvgVotesReceived,
        count(distinct p.Id) as PostsCount,
        count(distinct c.Id) as CommentCount,
        coalesce(u.Reputation, 0) as Reputation,
        rank() over (order by u.Reputation desc nulls last) as ReputationRank
    from Users u
    left join Badges b on u.Id = b.UserId
    left join (
        select PostOwnerId, count(*) as Count
        from (
            select PostOwnerId = p.OwnerUserId
            from Votes v
            join Posts p on p.Id = v.PostId
            -- Only upvotes and accepted votes counted here (simulates relevance)
            where v.VoteTypeId in (1, 2)
            group by p.OwnerUserId, v.Id
        ) votesData
        group by PostOwnerId
    ) v on u.Id = v.PostOwnerId
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
UserBestAnswers AS (
    select
        rha.ParentId as QuestionId,
        rha.Id as AnswerId,
        rha.OwnerUserId,
        rha.CreationDate,
        rha.Score,
        row_number() over (partition by rha.OwnerUserId order by rha.Score desc, rha.CreationDate desc) as BestAnswerRank
    from RecentHighScoringAnswers rha
),
QuestionsWithMetadata AS (
    select
        q.Id,
        q.Title,
        q.Tags,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        coalesce(a.AnswerId, -1) as BestAnswerId,
        u.OwnerUserId,
        u.Reputation,
        ut.BadgeCount
    from Posts q
    left join (
        select
            ParentId,
            max(Score) as BestScore
        from Posts
        where PostTypeId = 2 
        group by ParentId
    ) ans on ans.ParentId = q.Id
    left join Posts a on a.ParentId = q.Id and a.Score = ans.BestScore
    left join UserAggregate u on q.OwnerUserId = u.UserId
    left join UserAggregate ut on u.UserId = ut.UserId
    where q.PostTypeId = 1 -- question
      and q.CreationDate >= now() - interval '1 year'
),
DistinctTags AS (
    select 
        distinct unnest(string_to_array(substring(Tags from 2 for length(Tags) - 2), '><')) as Tag
    from Posts
    where PostTypeId = 1
      and Tags is not null
),
QuestionsPerTag AS (
    select
        dt.Tag, count(distinct q.Id) as QuestionCount
    from DistinctTags dt
    left join Posts q on q.Tags ilike concat('%<', dt.Tag, '>%') and q.PostTypeId = 1
    group by dt.Tag
),
ComplexUserStatus AS (
    select
        ua.UserId,
        case 
            when ua.ReputationRank <= 100 then 'Top 100'
            when ua.ReputationRank > 100 and ua.BadgeCount >= 10 then 'Experienced'
            when ua.BadgeCount < 10 and ua.CommentCount > 100 then 'Comment Active'
            else 'Regular'
        end as UserStatus
    from UserAggregate ua
),
FinalAggregation AS (
    select
        qwm.Id as QuestionId,
        qwm.Title,
        dp.Tag,
        qwm.CreationDate::date as CreationDay,
        qwm.Score as QuestionScore,
        rha.Score as BestAnswerScore,
        us.UserStatus,
        row_number() over (partition by qwm.Id order by rha.Score desc nulls last) as AnswerRank,
        LAG(qwm.Score) over (order by qwm.CreationDate) as PrevQuestionScore,
        CASE 
            WHEN qwm.Score > avg(qwm.Score) over ()
                 THEN 'AboveAvg'
            ELSE 'BelowAvg'
        END as ScoreQuality,
        sibling.LinkedExpertPosts,
        case when qwm.Tags ilike '%sql%' then true else false end as HasSqlTag
    from QuestionsWithMetadata qwm
    left join RecentHighScoringAnswers rha on rha.ParentId = qwm.Id and rha.AnswerRank=1
    left join ComplexUserStatus us on qwm.OwnerUserId = us.UserId
    left join Lateral (
        select 
            count(distinct pl.RelatedPostId) as LinkedExpertPosts
        from PostLinks pl
        JOIN Posts pz on pl.RelatedPostId = pz.Id and pz.OwnerUserId is not null
        JOIN UserAggregate ua on ua.UserId = pz.OwnerUserId and ua.ReputationRank < 500
        where pl.PostId = qwm.Id and pl.LinkTypeId = 1
    ) sibling on true
    cross join DistinctTags dp
    where qwm.Tags ilike concat('%<', dp.Tag, '>%')
)
select
    fa.CreationDay,
    fa.UserStatus,
    fa.HasSqlTag,
    string_agg(distinct fa.Tag, ',') as AssociatedTags,
    count(*) filter (where fa.ScoreQuality='AboveAvg') as AboveAvgCount,
    avg(fa.QuestionScore) as AvgScore,
    avg(fa.BestAnswerScore) filter (where fa.BestAnswerScore is not null) as AvgBestAnswerScore,
    avg(fa.LinkedExpertPosts) as AvgLinkedExpertPosts,
    bool_and(fa.HasSqlTag) over (partition by fa.UserStatus) as AllHaveSqlTagInStatus,
    max(row_number() over (order by CreationDay desc)) by StatusRows,

    (select count(distinct TagId)
     from RecursiveTagCounts rtcSub
     where rtcSub.ModeratorOnly = 'NO' and length(rtcSub.TagName) > 2 and rtcSub.TagName like '%sql%') as CountRelevantTags
from FinalAggregation fa
group by fa.CreationDay, fa.UserStatus, fa.HasSqlTag
order by fa.CreationDay desc, fa.UserStatus asc
limit 50;