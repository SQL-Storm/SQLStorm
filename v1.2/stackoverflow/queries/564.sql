-- {"query": "564.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1403} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount,0) as AnswerCount,
        coalesce(p.ViewCount,0) as ViewCount,
        row_number() over (order by t.Count desc, t.TagName) as Rank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(b.Id) as TotalBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        p.AcceptedAnswerId,
        count(c.Id) over (partition by p.Id) as CommentCountWindow,
        rank() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId in (1,2) -- questions and answers
),
TopPostsWithVotes as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        p.AcceptedAnswerId
    from Posts p
    left join (
        select
            PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by PostId
    ) v on v.PostId = p.Id
    where p.PostTypeId = 1 -- questions only
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where pht.Name = 'Post Closed'
),
QuestionsWithDetails as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        d.RelatedPostId as DuplicateOf,
        cr.CloseReason,
        cr.CloseDate,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges,
        ub.DisplayName as OwnerName,
        v.UpVotes,
        v.DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as UserTopQuestionRank
    from Posts p
    left join DuplicateLinks d on d.PostId = p.Id
    left join QuestionCloseReasons cr on cr.PostId = p.Id
    left join UserBadgeSummary ub on ub.UserId = p.OwnerUserId
    left join (
        select
            PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by PostId
    ) v on v.PostId = p.Id
    where p.PostTypeId = 1
)
select
    q.Id as QuestionId,
    q.Title,
    q.OwnerName,
    q.Score,
    q.ViewCount,
    q.Tags,
    q.GoldBadges,
    q.SilverBadges,
    q.BronzeBadges,
    q.TotalBadges,
    q.UpVotes,
    q.DownVotes,
    q.DuplicateOf,
    q.CloseReason,
    q.CloseDate,
    rtc.Rank as TagRank,
    rtc.Count as TagGlobalCount,
    rtc.AnswerCount as TagAnswerCount,
    rtc.ViewCount as TagViewCount,
    case 
        when q.AcceptedAnswerId is not null then 'Accepted'
        when q.CloseReason is not null then 'Closed'
        else 'Open'
    end as Status,
    concat(
        'Q:', q.Score, 
        ' | Views:', q.ViewCount, 
        ' | UpVotes:', q.UpVotes, 
        ' | DownVotes:', q.DownVotes, 
        ' | Badges(G/S/B):', q.GoldBadges, '/', q.SilverBadges, '/', q.BronzeBadges
    ) as Summary,
    (select count(*) from Comments c where c.PostId = q.Id and (c.Text like '%performance%' or c.Text like '%benchmark%')) as PerformanceCommentsCount,
    (select max(ph.CreationDate) from PostHistory ph where ph.PostId = q.Id and ph.PostHistoryTypeId in (4,5,6)) as LastEditDate
from QuestionsWithDetails q
left join RecursiveTagCounts rtc on rtc.TagName = split_part(q.Tags, '><', 1)
where q.Score > 10
  and (q.CloseReason is null or q.CloseReason = 'Needs details or clarity')
  and q.UserTopQuestionRank <= 5
order by q.Score desc, q.ViewCount desc
limit 50;