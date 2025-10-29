-- {"query": "2383.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1203} 
with RecursiveRecentPosts as (
    select p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId,
        p.AcceptedAnswerId, p.ParentId,
        row_number() over (partition by p.PostTypeId order by p.CreationDate desc) as rn
    from Posts p
    where p.CreationDate > current_date - interval '180 day'
),
TopQuestions as (
    select r.Id, r.Score, r.ViewCount, u.DisplayName as OwnerName, 
        (select count(*) from Comments c where c.PostId = r.Id and (c.Text ilike '%error%' or c.Text ilike '%fail%')) as ErrorCommentsCount,
        (select count(*) from Votes v where v.PostId = r.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = r.Id and v.VoteTypeId = 3) as DownVotes,
        (select string_agg(distinct tag.TagName, ', ') from Tags tag
            join Posts pt on pt.Tags is not null and tag.Id = any (
               select (regexp_split_to_table(substring(pt.Tags, 2, length(pt.Tags)-2), '><')::int)
            )
            where pt.Id = r.Id) as TagList,
        case when r.AcceptedAnswerId is not null then 'Accepted' else 'Unaccepted' end as AnswerStatus
    from RecursiveRecentPosts r
    left join Users u on u.Id = r.OwnerUserId
    where r.PostTypeId = 1 and r.rn <= 500
),
AnswerStats as (
    select p.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        min(p.Score) as MinAnswerScore,
        count(distinct case when p.OwnerUserId is null then null else p.OwnerUserId end) as DistinctAnswerers
    from RecursiveRecentPosts p
    where p.PostTypeId = 2
    group by p.ParentId
),
CloseInfo as (
    select ph.PostId, crt.Name as CloseReason, ph.CreationDate as CloseDateTime
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where pht.Name = 'Post Closed'
),
UserBadgeCounts as (
    select b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
FinalResults as (
    select tq.Id as QuestionId, tq.Score as QuestionScore, tq.ViewCount,
        tq.OwnerName, 
        ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
        tq.ErrorCommentsCount,
        tq.UpVotes, tq.DownVotes,
        as1.AnswerCount, as1.AvgAnswerScore, as1.MaxAnswerScore, as1.MinAnswerScore, as1.DistinctAnswerers,
        ci.CloseReason, ci.CloseDateTime,
        row_number() over (partition by as1.AnswerCount >= 5 order by tq.Score desc, tq.ViewCount desc) as ScoreRankWithinAnswerGroup,
        length(coalesce(tq.TagList, '')) as TagLength,
        case when position('sql' in lower(tq.TagList)) > 0 then 1 else 0 end as HasSqlTag
    from TopQuestions tq
    left join AnswerStats as1 on as1.QuestionId = tq.Id
    left join CloseInfo ci on ci.PostId = tq.Id
    left join UserBadgeCounts ub on ub.UserId = (select OwnerUserId from Posts where Id = tq.Id)
)
select 
    QuestionId, QuestionScore, ViewCount, OwnerName,
    coalesce(GoldBadges,0) as GoldBadges, coalesce(SilverBadges,0) as SilverBadges, coalesce(BronzeBadges,0) as BronzeBadges,
    ErrorCommentsCount, UpVotes, DownVotes,
    coalesce(AnswerCount,0) as AnswerCount, coalesce(AvgAnswerScore,0)::numeric(10,2) as AvgAnswerScore, MaxAnswerScore, MinAnswerScore, coalesce(DistinctAnswerers,0) as DistinctAnswerers,
    CloseReason, CloseDateTime,
    ScoreRankWithinAnswerGroup,
    TagLength,
    HasSqlTag,
    case 
        when CloseReason is null then 'Open'
        when lower(CloseReason) like '%duplicate%' then 'Duplicate'
        else 'Closed for other reason'
    end as PostStatus,
    lower(substr(OwnerName,1,1)) as OwnerNameInitial,
    substring(OwnerName from '(\\w+)') as OwnerNameFirstWord,
    sum(coalesce(AnswerCount,0)) over (partition by HasSqlTag order by QuestionScore desc rows between unbounded preceding and current row) as RunningAnswerCountByTag,
    count(*) over () as TotalQuestionsAnalyzed
from FinalResults
where (AnswerCount >= 3 or ScoreRankWithinAnswerGroup <= 10)
  and (HasSqlTag = 1 or CloseReason is null)
order by HasSqlTag desc, ScoreRankWithinAnswerGroup, QuestionScore desc, ViewCount desc
limit 100;