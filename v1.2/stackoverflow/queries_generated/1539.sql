-- {"query": "1539.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1370} 
with recursive UserScoreRanks as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(b.BadgeSummary, '') as BadgeSummary,
        dense_rank() over (
            order by u.Reputation desc nulls last, u.LastAccessDate desc nulls last
        ) as ReputationRank
    from 
        Users u
        left join (
            select
                UserId, 
                string_agg('['||Name||':'||Class||']', ',' order by Class, Name) as BadgeSummary
            from Badges
            group by UserId
        ) b on u.Id = b.UserId
    where
        u.Reputation > 1000
), PostWithAnswers as (
    select 
        p.Id as PostId,
        p.Title,
        p.Tags,
        p.Score as QuestionScore,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate as CreationDate,
        p.AcceptedAnswerId,
        count(a.Id) as AnswerCount,
        avg(coalesce(a.Score,0)) as AvgAnswerScore
    from 
        Posts p
        left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where 
        p.PostTypeId = 1
        and p.ClosedDate is NULL
    group by p.Id, p.Title, p.Tags, p.Score, p.ViewCount, p.OwnerUserId, p.CreationDate, p.AcceptedAnswerId
), AnswerComments as (
    select
        a.Id as AnswerId,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate
    from PostWithAnswers pwa
    join Posts a on a.ParentId = pwa.PostId and a.PostTypeId = 2
    left join Comments c on c.PostId = a.Id
    group by a.Id
), LatestPostEdits as (
    select distinct on (ph.PostId) 
        ph.PostId,
        ph.CreationDate as LastEditDate,
        ph.UserId as EditorUserId,
        ph.UserDisplayName as EditorDisplayName,
        ph.PostHistoryTypeId,
        ph.Comment as EditComment
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
    order by ph.PostId, ph.CreationDate desc
), RecursiveTagExplode as (
    select
        PostId,
        trim(regexp_split_to_table(substring(Tags from 2 for char_length(Tags) - 2), '><')) as Tag
    from Posts
    where PostTypeId = 1 and Tags is not null
), TagPopularity as (
    select
        Tag,
        count(*) as QuestionCount,
        avg(ViewCount) as AvgViews,
        max(Score) as MaxScore
    from Posts p
    join RecursiveTagExplode rte on rte.PostId = p.Id
    where p.PostTypeId = 1
    group by Tag
), UserCloseVotes as ( 
  select ph.UserId, count(*) as CloseVotesCast
  from PostHistory ph
  where ph.PostHistoryTypeId = 10 and ph.UserId is not null
  group by ph.UserId
), QuestionWithTopDuplicatesSup as (
    select 
        p.id, p.Title, count(pl.Id) as DupCount, max(pl.CreationDate) as LatestDupLinkDate
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3
    where p.PostTypeId = 1
    group by  p.id, p.Title
    having count(pl.Id) > 0
)
select 
    u.DisplayName,
    u.Reputation,
    u.CreationDate::date,
    u.BadgeSummary,
    pwa.Title,
    regexp_replace(pwa.Tags, '[<>]', ',', 'g') as TagsFormatted,
    pwa.Score as QuestionScore,
    pwa.ViewCount,
    pwa.AnswerCount,
    round(pwa.AvgAnswerScore::numeric,2) as AvgAnswerScore,
    ac.CommentCount,
    coalesce(ai.RankInfluence,0) as InfluenceIndex,
    max(pe.LastEditDate) as LatestEditTimestamp,
    tpop.Tag as TopTag,
    tpop.QuestionCount as QuestionsInTopTag,
    tpop.AvgViews as AvgViewsInTopTag,
    tpop.MaxScore as MaxAnswerScoreInTopTag,
    # Convention of lateral subqueries showing link counts and most recent dup post for questions the user owns
    coalesce(qdchuplicates.DupCount,0) as OwnedDuplicateCount,
    to_char(qdchuplicates.LatestDupLinkDate, 'YYYY-MM-DD') as LatestDupLinkDateFormatted,
    coalesce(ucv.CloseVotesCast, 0) as CloseVotesCast
from UserScoreRanks u
left join PostWithAnswers pwa on pwa.OwnerUserId = u.UserId
left join AnswerComments ac on ac.AnswerId = pwa.AcceptedAnswerId
left join LatestPostEdits pe on pe.PostId = pwa.PostId
left join lateral (
    select count(distinct a.Id) * weight_val as RankInfluence
    from Posts a 
    where a.OwnerUserId = u.UserId and a.PostTypeId = 2
    join LATERAL (
        select case
            when a.Score >= 20 then 20
            when a.Score >= 10 then 15
            when a.Score >= 5 then 10
            else 5 end as weight_val
        from Posts ax where ax.Id = a.Id 
    ) weights on true
) ai on true
left join lateral (
    select tpop2.Tag, tpop2.QuestionCount, tpop2.AvgViews, tpop2.MaxScore from (
                                                     select 
                                                        distinct tag, 
                                                        QuestionCount,
                                                        AvgViews,
                                                        MaxScore
                                                     from TagPopularity    	
                                                     order by QuestionCount desc limit 1
                                               ) tpop2
) tpop on true
left join QuestionWithTopDuplicatesSup qdchuplicates on qdchuplicates.id = pwa.PostId
left join UserCloseVotes ucv on u.UserId=ucv.UserId
where pwa.AcceptedAnswerId is not null
order by u.ReputationRank, pwa.Score desc NULLS LAST
limit 100;