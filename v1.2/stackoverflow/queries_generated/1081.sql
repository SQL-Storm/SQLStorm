-- {"query": "1081.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1889} 
with RecursiveTagHierarchy as (
    -- Recursive CTE to build tag usage hierarchy with question and answer counts
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.PostTypeId,
        case when p.PostTypeId = 1 then 1 else 0 end as QuestionCount,
        case when p.PostTypeId = 2 then 1 else 0 end as AnswerCount
    from Tags t
    left join Posts p on (p.Tags ilike concat('%<', t.TagName, '>%'))

    union all

    select
        r.Id,
        r.TagName,
        r.Count,
        p.Id,
        p.PostTypeId,
        case when p.PostTypeId = 1 then 1 else 0 end,
        case when p.PostTypeId = 2 then 1 else 0 end
    from RecursiveTagHierarchy r
    join Posts p on p.ParentId = r.PostId
    where r.PostId is not null
),

TagAggregates as (
    select
        Id,
        TagName,
        sum(QuestionCount) as TotalQuestions,
        sum(AnswerCount) as TotalAnswers,
        max(Count) as MaxTagCount
    from RecursiveTagHierarchy
    group by Id, TagName
),

UserScoreWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        rank() over (order by u.Reputation desc) as RepRank,
        sum(p.Score) over (partition by u.Id) as TotalPostScore,
        avg(p.Score) over (partition by u.Id) as AvgPostScore,
        dense_rank() over (order by count(p.Id) desc) as PostCountRank,
        count(p.Id) over (partition by u.Id) as PostCount
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
),

TopUsers as (
    select * from UserScoreWindow
    where RepRank <= 10
    order by RepRank
),

ComplexPostStats as (
    select
        p.Id,
        p.Title,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        case 
            when p.PostTypeId = 1 then
                (select count(*) from Posts a where a.ParentId = p.Id)
            else null
        end as AnswersCount,
        coalesce(p.Tags, '') as Tags,
        substring(
            regexp_replace(
                coalesce(p.Body, ''), 
                '<.*?>', 
                '', 
                'g'
            ), 1, 200) as PlainTextSnippet,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankWithinType
    from Posts p
    where p.CreationDate > current_date - interval '365 days'
),

FilteredHighRankQuestions as (
    select *
    from ComplexPostStats
    where PostTypeId = 1
      and RankWithinType <= 50
      and AnswersCount >= 5
      and ( 
          Tags ilike '%<sql>%'
          or Tags ilike '%<performance>%'
          or Tags ilike '%<query>%'
      )
),

AnswerWithCommentStats as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        count(distinct c.Id) as CommentCount,
        max(c.Score) as MaxCommentScore,
        string_agg(distinct coalesce("VoteTypes".Name, 'Unknown'), ',') as VoteTypes
    from Posts a
    left join Comments c on c.PostId = a.Id
    left join Votes v on v.PostId = a.Id
    left join VoteTypes on Votes.VoteTypeId = VoteTypes.Id
    where a.PostTypeId = 2
    group by a.Id, a.ParentId, a.OwnerUserId, a.Score, a.CreationDate
),

LatestPostHistoryEdits as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.CreationDate as LastEditDate,
        ph.Text as LastEditText,
        u.DisplayName as EditorName,
        ph.PostHistoryTypeId
    from PostHistory ph
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Body, Tags
    order by ph.PostId, ph.CreationDate desc
),

QuestionWithTopAnswerComments as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        q.CreationDate as QuestionCreationDate,
        awt.AnswerId,
        awt.AnswerScore,
        awt.CommentCount,
        awt.MaxCommentScore,
        awt.VoteTypes,
        lph.LastEditDate,
        lph.EditorName
    from FilteredHighRankQuestions q
    left join AnswerWithCommentStats awt on awt.QuestionId = q.Id
    left join LatestPostHistoryEdits lph on lph.PostId = q.Id
    where awt.AnswerScore = (select max(Score) from Posts where ParentId = q.Id)
),

DuplicatesAndLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    left join Posts p1 on p1.Id = pl.PostId
    left join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name in ('Duplicate', 'Linked')
),

FinalResultSet as (
    select
        qu.QuestionId,
        qu.Title as QuestionTitle,
        u.DisplayName as QuestionOwnerName,
        u.Reputation as QuestionOwnerRep,
        qu.QuestionCreationDate,
        qu.AnswerId,
        qu.AnswerScore,
        qu.CommentCount as AnswerCommentCount,
        qu.MaxCommentScore as AnswerMaxCommentScore,
        qu.VoteTypes as AnswerVoteTypes,
        qu.LastEditDate as QuestionLastEditDate,
        qu.EditorName as QuestionLastEditor,
        da.LinkTypeName,
        da.RelatedPostId,
        da.RelatedPostTitle,
        ta.TotalQuestions as TagQuestionCount,
        ta.TotalAnswers as TagAnswerCount
    from QuestionWithTopAnswerComments qu
    left join Users u on u.Id = qu.QuestionOwner
    left join DuplicatesAndLinks da on da.PostId = qu.QuestionId
    left join TagAggregates ta on ta.TagName = any(string_to_array(replace(replace(qu.Title, '<', ''), '>', ''), ' '))
    where (qu.AnswerScore > 5 or qu.CommentCount > 3)
      and (da.LinkTypeName is null or da.LinkTypeName = 'Duplicate')
)

select distinct
    fr.*,
    case
        when fr.AnswerScore is null then 'No top answer yet'
        when fr.AnswerScore > 20 then 'Highly scored answer'
        when fr.AnswerScore between 10 and 20 then 'Moderately scored answer'
        else 'Low scored answer'
    end as AnswerScoreCategory,
    coalesce(fr.QuestionLastEditDate::date, fr.QuestionCreationDate::date) as RelevantDate,
    (select count(1) from Votes v where v.PostId = fr.QuestionId and v.VoteTypeId = 2) as QuestionUpVotes,
    (select count(1) from Votes v where v.PostId = fr.QuestionId and v.VoteTypeId = 3) as QuestionDownVotes,
    (select max(score) from Comments c where c.PostId = fr.AnswerId) as MaxAnswerCommentScore,
    (select count(*) from Badges b where b.UserId = fr.QuestionOwner and b.Class = 1) as GoldBadgesOfOwner,
    (select count(*) from Badges b where b.UserId = fr.QuestionOwner and b.Class = 2) as SilverBadgesOfOwner,
    (select count(*) from Badges b where b.UserId = fr.QuestionOwner and b.Class = 3) as BronzeBadgesOfOwner
from FinalResultSet fr
order by fr.QuestionCreationDate desc
limit 100;