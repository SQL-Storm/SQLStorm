-- {"query": "446.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1330} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        coalesce(sum(vt2.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vt3.DownVotes),0) as TotalDownVotes,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from
        Users u
        left join Posts p on p.OwnerUserId = u.Id
        left join (
            select
                v.PostId,
                count(*) filter (where vt.Name = 'UpMod') as UpVotes,
                count(*) filter (where vt.Name = 'DownMod') as DownVotes
            from Votes v
            join VoteTypes vt on vt.Id = v.VoteTypeId
            group by v.PostId
        ) vt2 on vt2.PostId = p.Id
        left join (
            select
                v.PostId,
                count(*) filter (where vt.Name = 'DownMod') as DownVotes
            from Votes v
            join VoteTypes vt on vt.Id = v.VoteTypeId
            group by v.PostId
        ) vt3 on vt3.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopQuestions as (
    select
        p.Id as QuestionId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.AcceptedAnswerId,
        count(distinct a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        bool_or(p.ClosedDate is not null) as IsClosed,
        string_agg(distinct ph.Comment, ' | ' order by ph.CreationDate desc) filter (where ph.PostHistoryTypeId = 10) as CloseReasons
    from
        Posts p
        left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
        left join Users u on u.Id = p.OwnerUserId
        left join PostHistory ph on ph.PostId = p.Id
    where
        p.PostTypeId = 1
        and p.CreationDate > now() - interval '1 year'
    group by p.Id, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, u.DisplayName, p.AcceptedAnswerId, p.ClosedDate
),
AnswerDetails as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.Id as AnswererId,
        u.DisplayName as AnswererName,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from
        Posts a
        join Users u on u.Id = a.OwnerUserId
    where
        a.PostTypeId = 2
),
UserBadgeStats as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
),
CloseReasonCounts as (
    select
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id::text = ph.Comment
    where ph.PostHistoryTypeId = 10
    group by ph.Comment, crt.Name
    order by CloseCount desc
)
select
    r.UserId,
    r.DisplayName,
    r.Reputation,
    r.QuestionCount,
    r.AnswerCount,
    r.TotalPostScore,
    r.TotalUpVotes,
    r.TotalDownVotes,
    coalesce(ub.GoldBadges,0) as GoldBadges,
    coalesce(ub.SilverBadges,0) as SilverBadges,
    coalesce(ub.BronzeBadges,0) as BronzeBadges,
    tq.QuestionId,
    tq.Title as QuestionTitle,
    tq.Score as QuestionScore,
    tq.ViewCount as QuestionViews,
    tq.IsClosed,
    tq.CloseReasons,
    ad.AnswerId,
    ad.AnswerScore,
    ad.AnswerRank,
    ad.AnswererName,
    dl.RelatedPostId as DuplicateOfQuestionId,
    dl.RelatedPostTitle as DuplicateOfQuestionTitle,
    crc.CloseReasonName,
    crc.CloseCount
from RecursiveUserActivity r
left join UserBadgeStats ub on ub.UserId = r.UserId
left join TopQuestions tq on tq.OwnerUserId = r.UserId
left join AnswerDetails ad on ad.QuestionId = tq.QuestionId and ad.AnswerRank = 1
left join DuplicateLinks dl on dl.PostId = tq.QuestionId
left join CloseReasonCounts crc on crc.CloseReasonId = any(string_to_array(tq.CloseReasons, ' | '))
where r.UserRank <= 50
order by r.Reputation desc, tq.Score desc, ad.AnswerScore desc
limit 100;