with RecursiveRecentPosts as (
    select p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId,
        p.AcceptedAnswerId, p.ParentId,
        row_number() over (partition by p.PostTypeId order by p.CreationDate desc) as rn
    from Posts p
    where p.CreationDate > (cast('2024-10-01' as date) - interval '180' day)
),
TopQuestions as (
    select r.Id, r.Score, r.ViewCount, u.DisplayName as OwnerName, 
        (select count(*) from Comments c where c.PostId = r.Id and (lower(c.Text) like '%error%' or lower(c.Text) like '%fail%')) as ErrorCommentsCount,
        (select count(*) from Votes v where v.PostId = r.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = r.Id and v.VoteTypeId = 3) as DownVotes,
        (select string_agg(distinct tag.TagName, ', ') from Tags tag
            join Posts pt on pt.Id = r.Id and pt.Tags is not null
            cross join lateral (
                -- split tags stored like '<tag1><tag2>' into rows in a SQL-dialect-compatible way
                select trim(t) as tag_text
                from (
                    -- Replace the angle-bracket wrapped tag string into a delimited string, then split using a generic split simulated via recursive CTE
                    select value as t
                    from (
                        select replace(substr(pt.Tags, 2, length(pt.Tags)-2), '><', '||DELIM||') as delimited
                    ) d,
                    lateral (
                        -- split the delimited string into rows by repeatedly extracting up to the delimiter
                        select split_values.value
                        from (
                            with recursive split_values_cte(pos, rest, value) as (
                                select 1 as pos,
                                       d.delimited as rest,
                                       case when position('||DELIM||' in d.delimited) = 0 then d.delimited
                                            else substr(d.delimited, 1, position('||DELIM||' in d.delimited)-1) end as value
                                union all
                                select pos+1,
                                       case when position('||DELIM||' in rest) = 0 then '' else substr(rest, position('||DELIM||' in rest)+8) end,
                                       case when position('||DELIM||' in rest) = 0 then rest
                                            else substr(rest, 1, position('||DELIM||' in rest)-1) end
                                from split_values_cte
                                where rest <> '' and position('||DELIM||' in rest) > 0
                            )
                            select value from split_values_cte where value is not null and value <> ''
                        ) split_values(value)
                    ) split_result
                ) as tagrows
            ) as splitvals
            where tag.Id = (
                select t2.Id from Tags t2 where lower(t2.TagName) = lower(splitvals.tag_text) limit 1
            )
        ) as TagList,
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
        count(distinct p.OwnerUserId) as DistinctAnswerers
    from RecursiveRecentPosts p
    where p.PostTypeId = 2
    group by p.ParentId
),
CloseInfo as (
    select ph.PostId, crt.Name as CloseReason, ph.CreationDate as CloseDateTime
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
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
        row_number() over (partition by (case when as1.AnswerCount >= 5 then 1 else 0 end) order by tq.Score desc, tq.ViewCount desc) as ScoreRankWithinAnswerGroup,
        length(coalesce(tq.TagList, '')) as TagLength,
        case when position('sql' in lower(coalesce(tq.TagList, ''))) > 0 then 1 else 0 end as HasSqlTag
    from TopQuestions tq
    left join AnswerStats as1 on as1.QuestionId = tq.Id
    left join CloseInfo ci on ci.PostId = tq.Id
    left join UserBadgeCounts ub on ub.UserId = (select OwnerUserId from Posts where Id = tq.Id)
)
select 
    QuestionId, QuestionScore, ViewCount, OwnerName,
    coalesce(GoldBadges,0) as GoldBadges, coalesce(SilverBadges,0) as SilverBadges, coalesce(BronzeBadges,0) as BronzeBadges,
    ErrorCommentsCount, UpVotes, DownVotes,
    coalesce(AnswerCount,0) as AnswerCount, cast(coalesce(AvgAnswerScore,0) as numeric(10,2)) as AvgAnswerScore, MaxAnswerScore, MinAnswerScore, coalesce(DistinctAnswerers,0) as DistinctAnswerers,
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
    regexp_replace(OwnerName, '^(\\w+).*$', '\\1') as OwnerNameFirstWord,
    sum(coalesce(AnswerCount,0)) over (partition by HasSqlTag order by QuestionScore desc rows between unbounded preceding and current row) as RunningAnswerCountByTag,
    count(*) over () as TotalQuestionsAnalyzed
from FinalResults
where (coalesce(AnswerCount,0) >= 3 or ScoreRankWithinAnswerGroup <= 10)
  and (HasSqlTag = 1 or CloseReason is null)
group by
    QuestionId, QuestionScore, ViewCount, OwnerName,
    GoldBadges, SilverBadges, BronzeBadges,
    ErrorCommentsCount, UpVotes, DownVotes,
    AnswerCount, AvgAnswerScore, MaxAnswerScore, MinAnswerScore, DistinctAnswerers,
    CloseReason, CloseDateTime,
    ScoreRankWithinAnswerGroup,
    TagLength,
    HasSqlTag,
    OwnerNameInitial, OwnerNameFirstWord,
    PostStatus
order by HasSqlTag desc, ScoreRankWithinAnswerGroup, QuestionScore desc, ViewCount desc
limit 100;