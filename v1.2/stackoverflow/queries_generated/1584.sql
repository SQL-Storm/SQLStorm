-- {"query": "1584.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1334} 

with RecursiveUserBadges AS (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        roi.MinBadgeClass
    from Users u
    join Badges b on u.Id = b.UserId
    join (
        select UserId, min(Class) as MinBadgeClass
        from Badges
        group by UserId
    ) roi on b.UserId = roi.UserId and b.Class = roi.MinBadgeClass

    union all
    
    select 
        b.UserId,
        null,
        null,
        null,
        roi.MinBadgeClass
    from Badges b
    join (
        select UserId, min(Class) as MinBadgeClass
        from Badges
        group by UserId
    ) roi on b.UserId = roi.UserId and b.Class > roi.MinBadgeClass
    where b.Name like '%Pro%'
),
RankedQuestions AS (
    select
        p.Id,
        p.Title,
        p.ViewCount,
        OwnerUserId,
        coalesce(SequenceNr, 0) as SeqNum,
        Rank() OVER (
            PARTITION BY p.OwnerUserId 
            ORDER BY p.ViewCount desc, p.CreationDate desc NULLS LAST
        ) as OwnerQuestionRank
    from (
        select
            *,
            row_number() over(
                partition by OwnerUserId
                order by ViewCount desc
            ) as SequenceNr
        from Posts
        where PostTypeId = 1
          and ViewCount is not null
    ) p
),
UserActivitySummary as (
    select 
        u.Id as UserId,
        u.DisplayName,
        date_trunc('month', u.CreationDate) as UserCreatedMonth,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        sum(v.VoteTypeId = 2)::int as UpVotesReceived,
        sum(v.VoteTypeId = 3)::int as DownVotesReceived,
        coalesce(sum(case when oh.PostHistoryTypeId = 10 then 1 else 0 end), 0) as TimesPostClosed,
        exists (
          select 1 from Badges b 
          where b.UserId = u.Id and b.Class = 1
        ) AS HasGoldBadge
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    left join PostHistory oh on oh.PostId = p.Id
    group by u.Id, u.DisplayName, u.CreationDate
),
LinkedParentAnswers AS (
    select
        pa.Id as AnswerId,
        pa.ParentId,
        coalesce(pl.LinkTypeId, 0) as LinkTypeId,
        lt.Name as LinkTypeName,
        pa.CreationDate,
        pa.Score,
        prow.AnswerJaScoreAvg,
        Row_Number() OVER (
            partition by pa.ParentId 
            order by pa.Score desc nulls last, pa.CreationDate asc
        ) as AnswerRankForQuestion
    from Posts pa
    left join PostLinks pl ON pl.PostId = pa.Id
    left join LinkTypes lt ON lt.Id = pl.LinkTypeId
    left join Lateral (
      select avg(pdto.Score) as AnswerJaScoreAvg
      from Posts pdto
      where pdto.ParentId = pa.ParentId and pdto.PostTypeId = 2
    ) prow on true
    where pa.PostTypeId = 2
),
QuestionTagsClean AS (
  select
      p.Id,
      unnest(string_to_array(trim(both '<>' from p.Tags),'><')) as Tag
  from posts p
  where p.Tags is not null and p.PostTypeId = 1
)

select 
    u.Id as UserId,
    u.DisplayName as UserName,
    uas.QuestionsAsked,
    count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
    rq.SeqNum,
    rq.Title as TopQuestionTitleGuessingConcattedScores,
    (
        select count(*) 
        from Posts as ps 
        where ps.OwnerUserId = u.Id and ps.PostTypeId = 1 and ps.ViewCount > 1000
    ) as PopularQuestionsCount,
    uas.UpVotesReceived,
    uas.DownVotesReceived,
    Cardinality(array_agg(Distinct qtc.Tag)) as UniqueTagsCount,
    coalesce(ll.LinkTypeName, 'NoDuplicateOrMerge') as MostCommonLinkTypeForAnswering, 
    sum(ll.Score) filter (where ll.AnswerRankForQuestion = 1) as SumScoresStartingPositions,
    rank() over (order by uas.QuestionsAsked desc, uas.UpVotesReceived desc) as RankTopUser,
    avg(u.Reputation) over() as GlobalAverageReputation,
    bool_or(uac.HasGoldBadge) over (partition by u.Id) as UserLikelyExperienced
from 
    Users u
left join RecursiveUserBadges rub on rub.UserId = u.Id
left join Badges b on b.UserId = u.Id
left join RankedQuestions rq on rq.OwnerUserId = u.Id and rq.OwnerQuestionRank = 1
left join UserActivitySummary uas on uas.UserId = u.Id
left join LinkedParentAnswers ll on ll.ParentId IN (
        select Id from Posts where OwnerUserId = u.Id and PostTypeId = 1 limit 5
    )
left join QuestionTagsClean qtc on qtc.Id IN (
    select Id from Posts where OwnerUserId = u.Id and PostTypeId = 1 limit 7
)
left join UserActivitySummary uac on uac.UserId = u.Id
where u.CreationDate between now() - interval '5 years' and now()
  and uas.QuestionsAsked > 0
group by 
    u.Id,
    u.DisplayName,
    uas.QuestionsAsked,
    rq.SeqNum,
    rq.Title,
    uas.UpVotesReceived,
    uas.DownVotesReceived,
    ll.LinkTypeName,
    uac.HasGoldBadge
order by 
    uas.QuestionsAsked desc, uas.UpVotesReceived desc
limit 100;
